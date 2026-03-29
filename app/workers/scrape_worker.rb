# frozen_string_literal: true

# Sidekiq worker that processes web scraping jobs
# Orchestrates the scraping flow: Find Job -> Call ScraperStrategy -> Update Job Status
class ScrapeWorker
  include Sidekiq::Worker

  sidekiq_options retry: 5, queue: :default

  # @param job_id [String] The MongoDB _id of the ScrapeJob document
  def perform(job_id)
    job = ScrapeJob.find(job_id)
    strategy = ScraperStrategy.new

    Rails.logger.info("Processing scrape job #{job_id} for URL: #{job.url}")

    response = strategy.execute(url: job.url)
    job.mark_done!(response)

    strategy_used = response[:strategy] || "unknown"
    Rails.logger.info("Successfully scraped #{job.url}. Status: #{response[:status]}, Strategy: #{strategy_used}")
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
    Rails.logger.error(e.backtrace.join("\n"))
    job&.mark_failed!(e.message)
    raise
  end
end
