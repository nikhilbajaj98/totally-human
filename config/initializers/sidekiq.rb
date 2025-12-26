# frozen_string_literal: true

# Sidekiq configuration
# Uses Redis URL from environment variable (set in docker-compose.yml)
# Defaults to localhost for local development, or 'redis' hostname in Docker
redis_url = ENV.fetch("REDIS_URL") do
  # Default to localhost for local development, Docker will override via env var
  "redis://localhost:6379/0"
end

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end

