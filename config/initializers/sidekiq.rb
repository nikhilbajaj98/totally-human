# frozen_string_literal: true

redis_url = ENV.fetch("REDIS_URL") { "redis://localhost:6379/0" }

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }

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
