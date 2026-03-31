# frozen_string_literal: true

# Sidekiq worker that processes web scraping jobs.
# Integrates rate limiting (per-domain + global), scraping strategy (free/premium),
# parsing, and dead letter queue tracking.
class ScrapeWorker
  include Sidekiq::Worker

  sidekiq_options retry: 5, queue: :default

  RETRY_DELAY_BASE = 5
  RETRY_DELAY_JITTER = 5

  def perform(job_id)
    job = ScrapeJob.find(job_id)
    domain = extract_domain(job.url)

    rate_limiter = RateLimiter.new
    acquired = rate_limiter.acquire!(domain)

    unless acquired
      delay = RETRY_DELAY_BASE + rand(RETRY_DELAY_JITTER)
      Rails.logger.info("RateLimiter: Slot unavailable for #{domain}, re-enqueueing job #{job_id} in #{delay}s")
      self.class.perform_in(delay, job_id)
      return
    end

    begin
      strategy = ScraperStrategy.new

      Rails.logger.info("Processing scrape job #{job_id} for URL: #{job.url}")
      response = ScrapePayload.utf8(strategy.execute(url: job.url))

      parser = Parsers::Registry.for_url(job.url)
      parsed = parser.safe_parse(response[:html] || "")
      parser_name = parser.class.name.demodulize

      job.mark_done!(response, parsed_data: ScrapePayload.utf8(parsed), parser_used: parser_name)

      strategy_used = response[:strategy] || "unknown"
      Rails.logger.info("Successfully scraped #{job.url}. Strategy: #{strategy_used}, Parser: #{parser_name}")
    rescue Mongoid::Errors::DocumentNotFound => e
      Rails.logger.error("ScrapeJob #{job_id} not found: #{e.message}")
      raise
    rescue ScraperStrategy::BudgetExceededError => e
      Rails.logger.error("Budget exceeded for job #{job_id}: #{e.message}")
      job&.mark_failed!(e.message)
      raise
    rescue ScraperStrategy::Error => e
      Rails.logger.error("Scraper strategy error for job #{job_id}: #{e.class} - #{e.message}")
      job&.mark_failed!(e.message)
      raise
    rescue StandardError => e
      Rails.logger.error("Unexpected error processing job #{job_id}: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.first(5).join("\n"))
      job&.mark_failed!(e.message)
      raise
    ensure
      rate_limiter&.release!(domain) if acquired
    end
  end

  private

  def extract_domain(url)
    URI.parse(url).host || "unknown"
  rescue URI::InvalidURIError
    "unknown"
  end
end
