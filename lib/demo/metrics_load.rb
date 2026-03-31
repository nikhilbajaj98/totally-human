# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Demo
  # Fire-and-forget POST /scrape_jobs to drive worker-side Yabeda counters (Grafana).
  class MetricsLoad
    DEFAULT_URLS = [
      "https://news.ycombinator.com/",
      "https://news.ycombinator.com/newest",
      "https://docs.python.org/3/tutorial/index.html",
      "https://example.com/",
      "https://www.wikipedia.org/wiki/Web_scraping",
      "https://www.google.com/search?q=prometheus+metrics",
      "https://www.amazon.com/s?k=batteries",
      "https://www.amazon.com/dp/B07ZPKBL9V"
    ].freeze

    def self.fire(api_base: nil, count: nil, sleep_ms: nil)
      base = (api_base || ENV.fetch("DEMO_API_URL", "http://127.0.0.1:3000")).to_s.chomp("/")
      total = (count || ENV.fetch("DEMO_LOAD_COUNT", "60").to_i).clamp(1, 5_000)
      pause = (sleep_ms || ENV.fetch("DEMO_LOAD_SLEEP_MS", "25").to_i).clamp(0, 5_000)

      uri = URI("#{base}/scrape_jobs")
      puts "demo:load → POST #{total} jobs to #{base} (sleep #{pause}ms between posts)"

      posted = 0
      total.times do |i|
        url = DEFAULT_URLS[i % DEFAULT_URLS.size]
        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        req.body = { url: url }.to_json

        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 10
        http.read_timeout = 10
        http.use_ssl = (uri.scheme == "https")
        res = http.request(req)
        posted += 1 if res.code.to_i == 201

        sleep(pause / 1000.0) if pause.positive?
      rescue StandardError => e
        warn "  POST #{i + 1}/#{total} failed: #{e.message}"
      end

      puts "Enqueued #{posted}/#{total} jobs (200 OK from API). Worker will process — watch Grafana (~15s scrape + processing time)."
      posted
    end
  end
end
