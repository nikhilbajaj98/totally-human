# frozen_string_literal: true

# Sidekiq worker that processes web scraping jobs
# Orchestrates the scraping flow: Find Job -> Call MaskServiceClient -> Update Job Status
class ScrapeWorker
  include Sidekiq::Worker

  # Sidekiq configuration
  sidekiq_options retry: 5, queue: :default

  # Process a scraping job
  #
  # @param job_id [String] The MongoDB _id of the ScrapeJob document
  def perform(job_id)
    job = ScrapeJob.find(job_id)
    client = MaskServiceClient.new

    Rails.logger.info("Processing scrape job #{job_id} for URL: #{job.url}")

    response = client.fetch(url: job.url)
    job.mark_done!(response)

    Rails.logger.info("Successfully scraped #{job.url}. Status: #{response[:status]}")
  rescue Mongoid::Errors::DocumentNotFound => e
    Rails.logger.error("ScrapeJob #{job_id} not found: #{e.message}")
    raise # Re-raise to trigger Sidekiq retry if job appears later
  rescue MaskServiceClient::Error => e
    Rails.logger.error("Mask service error for job #{job_id}: #{e.class} - #{e.message}")
    # Job might not be loaded if error occurred before find, so check if it exists
    job&.mark_failed!(e.message)
    raise # Re-raise to trigger Sidekiq retry
  rescue StandardError => e
    Rails.logger.error("Unexpected error processing job #{job_id}: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    # Job might not be loaded if error occurred before find, so check if it exists
    job&.mark_failed!(e.message)
    raise # Re-raise to trigger Sidekiq retry
  end
end

