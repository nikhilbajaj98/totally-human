# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Demo
  # HTTP-driven demo: POST jobs, poll until done/failed/dead, print colored summary.
  class Runner
    POLL_SECONDS = 2
    JOB_TIMEOUT_SECONDS = 120

    DEMO_JOBS = [
      { label: "Hacker News", url: "https://news.ycombinator.com/" },
      { label: "Article (Python tutorial)", url: "https://docs.python.org/3/tutorial/index.html" },
      { label: "Amazon search (SERP)", url: "https://www.amazon.com/s?k=usb+hub&dc" },
      { label: "Amazon product (PDP)", url: "https://www.amazon.com/dp/B07ZPKBL9V" },
      { label: "Google SERP", url: "https://www.google.com/search?q=openssl+library" }
    ].freeze

    def initialize(api_base: nil)
      @api_base = (api_base || ENV.fetch("DEMO_API_URL", "http://127.0.0.1:3000")).to_s.chomp("/")
    end

    def run
      $stdout.sync = true
      puts Demo::Colors.bold("TotallyHuman demo — submitting #{DEMO_JOBS.size} jobs to #{@api_base}")
      puts Demo::Colors.dim("Ensure api + worker + mask-service are running (e.g. docker compose up).")
      puts

      wall_start = monotonic_ms
      submissions = []

      DEMO_JOBS.each do |entry|
        id = post_job(entry[:url])
        submissions << { id: id, label: entry[:label], url: entry[:url], start_ms: monotonic_ms }
        puts Demo::Colors.cyan("  enqueued  #{entry[:label]}  id=#{id}")
      rescue StandardError => e
        puts Demo::Colors.red("  FAILED to enqueue #{entry[:label]}: #{e.message}")
        submissions << { id: nil, label: entry[:label], url: entry[:url], error: e.message, start_ms: monotonic_ms }
      end

      puts
      puts Demo::Colors.bold("Polling (timeout #{JOB_TIMEOUT_SECONDS}s per job)…")

      results = submissions.map do |sub|
        if sub[:id].nil?
          sub.merge(status: "enqueue_failed", elapsed_s: 0)
        else
          poll_job(sub)
        end
      end

      wall_ms = monotonic_ms - wall_start
      print_summary(results, wall_ms)
    end

    private

    def monotonic_ms
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
    end

    def post_job(url)
      uri = URI("#{@api_base}/scrape_jobs")
      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req.body = { url: url }.to_json

      response = http_request(uri, req)
      unless response.code.to_i == 201
        raise "POST #{uri} → #{response.code}: #{response.body.to_s[0, 200]}"
      end

      body = JSON.parse(response.body)
      id = body["id"]
      raise "missing job id in response" if id.blank?

      id
    end

    def poll_job(sub)
      id = sub[:id]
      deadline = monotonic_ms + (JOB_TIMEOUT_SECONDS * 1000)
      last_payload = nil

      loop do
        break if monotonic_ms > deadline

        uri = URI("#{@api_base}/scrape_jobs/#{id}")
        req = Net::HTTP::Get.new(uri)
        response = http_request(uri, req)
        unless response.code.to_i == 200
          sleep POLL_SECONDS
          next
        end

        last_payload = JSON.parse(response.body)
        status = last_payload["status"]
        if %w[done failed dead].include?(status)
          elapsed = ((monotonic_ms - sub[:start_ms]) / 1000.0).round(2)
          line = format_result_line(sub[:label], last_payload, elapsed)
          puts(status == "done" ? Demo::Colors.green(line) : Demo::Colors.red(line))
          return sub.merge(status: status, payload: last_payload, elapsed_s: elapsed)
        end

        sleep POLL_SECONDS
      end

      puts Demo::Colors.yellow("  TIMEOUT  #{sub[:label]}  id=#{id}")
      sub.merge(status: "timeout", payload: last_payload, elapsed_s: JOB_TIMEOUT_SECONDS)
    end

    def format_result_line(label, payload, elapsed)
      st = payload["status"]
      parser = payload["parser_used"] || "—"
      strategy = payload.dig("response_body", "strategy") || "—"
      preview = parsed_preview(payload["parsed_data"])
      %(#{label} | #{st} | #{elapsed}s | strategy=#{strategy} | parser=#{parser} | #{preview})
    end

    def parsed_preview(parsed)
      return "no parsed_data" if parsed.nil? || parsed.empty?

      keys = parsed.keys
      head = keys.first(4).join(", ")
      extra = keys.size > 4 ? "…" : ""

      if parsed["organic_results"].is_a?(Array)
        %(organic=#{parsed["organic_results"].size})
      elsif parsed["products"].is_a?(Array)
        %(products=#{parsed["products"].size})
      elsif parsed["stories"].is_a?(Array)
        %(stories=#{parsed["stories"].size})
      elsif parsed["title"].present?
        t = parsed["title"].to_s.tr("\n", " ")[0, 60]
        %(title="#{t}…")
      elsif parsed["robot_check"]
        "robot_check=#{parsed["robot_check"]}"
      else
        "keys=[#{head}#{extra}]"
      end
    end

    def print_summary(results, wall_ms)
      puts
      puts Demo::Colors.bold("— Summary —")

      terminal = results.size
      done = results.count { |r| r[:status] == "done" }
      failed = results.count { |r| r[:status].in?(%w[failed dead timeout enqueue_failed]) || r[:error] }
      ok_pct = terminal.positive? ? ((done.to_f / terminal) * 100).round : 0

      strategies = Hash.new(0)
      parsers = Hash.new(0)

      results.each do |r|
        next if r[:payload].nil?

        s = r[:payload].dig("response_body", "strategy")
        strategies[s.to_s] += 1 if s.present?
        p = r[:payload]["parser_used"]
        parsers[p.to_s] += 1 if p.present?
      end

      puts "  Wall time:     #{(wall_ms / 1000.0).round(2)}s"
      puts "  Jobs:          #{results.size} (#{done} done, #{failed} failed/timeout)"
      puts "  Success rate:  #{ok_pct}% (of terminal outcomes)"
      puts "  Strategies:    #{strategies.inspect}" if strategies.any?
      puts "  Parsers:       #{parsers.inspect}" if parsers.any?
      puts
      puts Demo::Colors.dim("Fetch full JSON: GET #{@api_base}/scrape_jobs/:id?format_type=parsed")
      puts Demo::Colors.dim("Grafana: http://localhost:3001 (after demo, metrics may take ~15s to scrape)")
    end

    def http_request(uri, request)
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 15
      http.read_timeout = JOB_TIMEOUT_SECONDS
      http.use_ssl = (uri.scheme == "https")
      http.request(request)
    end
  end
end
