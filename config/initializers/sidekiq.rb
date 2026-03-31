# frozen_string_literal: true

redis_url = ENV.fetch("REDIS_URL") { "redis://localhost:6379/0" }

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }

  # Dead letter queue: when all Sidekiq retries are exhausted, mark the job as permanently dead.
  config.death_handlers << ->(job, _exception) do
    job_id = job["args"]&.first
    if job_id
      scrape_job = ScrapeJob.find(job_id)
      scrape_job.mark_dead!("All #{ScrapeJob::MAX_RETRIES} retries exhausted: #{job["error_message"]}")
      Rails.logger.error("ScrapeJob #{job_id} moved to dead letter queue after all retries exhausted")
    end
  rescue Mongoid::Errors::DocumentNotFound
    Rails.logger.error("Death handler: ScrapeJob #{job_id} not found")
  rescue StandardError => e
    Rails.logger.error("Death handler error: #{e.class} - #{e.message}")
  end

  config.on(:startup) do
    require "webrick"
    require "rackup/handler/webrick"
    require "yabeda/prometheus"

    metrics_port = ENV.fetch("WORKER_METRICS_PORT", 9394).to_i

    Thread.new do
      Rackup::Handler::WEBrick.run(
        Yabeda::Prometheus::Exporter,
        Port: metrics_port,
        Host: "0.0.0.0",
        Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN),
        AccessLog: []
      )
    rescue => e
      $stderr.puts("[METRICS] Failed to start worker metrics server: #{e.class}: #{e.message}")
      $stderr.puts(e.backtrace.first(5).join("\n"))
    end

    Rails.logger.info("Worker metrics server starting on port #{metrics_port}")
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end
