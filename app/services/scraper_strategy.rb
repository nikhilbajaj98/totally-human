# frozen_string_literal: true

require "redis"

# Strategy pattern for cost-aware scraping with fallback logic
# Primary: Free mask-service (TLS fingerprint spoofing)
# Fallback: Premium API (paid service) when mask-service fails
class ScraperStrategy
  class Error < StandardError; end
  class BudgetExceededError < Error; end

  # HTTP status codes that trigger fallback to premium API
  FALLBACK_STATUS_CODES = [ 403, 429, 500 ].freeze

  # Redis key for tracking premium API usage
  PREMIUM_USAGE_KEY = "totallyhuman:premium_usage"

  # Default budget limit (configurable via environment variable)
  DEFAULT_BUDGET_LIMIT = 1000

  def initialize
    @mask_client = MaskServiceClient.new
    @premium_client = ScraperApiClient.new
    @budget_limit = ENV.fetch("PREMIUM_BUDGET_LIMIT", DEFAULT_BUDGET_LIMIT).to_i
    @redis = redis_client
  end

  # Execute the scraping strategy with fallback logic
  #
  # @param url [String] The URL to scrape
  # @param proxy [String, nil] Optional proxy URL
  # @return [Hash] Response containing :status, :html, :headers, :error, :error_message, :strategy
  # @raise [BudgetExceededError] If premium budget limit is exceeded
  # @raise [Error] If both strategies fail
  def execute(url:, proxy: nil)
    # Step 1: Try free mask-service first
    Rails.logger.info("ScraperStrategy: Attempting free mask-service for #{url}")
    response = @mask_client.fetch(url: url, proxy: proxy)

    # Step 2: Check if we should fallback
    if should_fallback?(response)
      Rails.logger.warn("ScraperStrategy: Mask service returned status #{response[:status]}, switching to premium API")
      return fallback_to_premium(url: url)
    end

    # Success with free service
    Rails.logger.info("ScraperStrategy: Successfully scraped #{url} using free mask-service")
    response.merge(strategy: "free")
  rescue MaskServiceClient::Error => e
    # Network/timeout errors from mask-service trigger fallback
    Rails.logger.warn("ScraperStrategy: Mask service error (#{e.class}), switching to premium API: #{e.message}")
    fallback_to_premium(url: url)
  end

  private

  def should_fallback?(response)
    # Fallback on error responses or specific HTTP status codes
    return true if response[:error]
    return true if FALLBACK_STATUS_CODES.include?(response[:status])
    return true if response[:status] >= 500 # Any 5xx error

    false
  end

  def fallback_to_premium(url:)
    # Step 3: Check budget before using premium
    check_budget!

    Rails.logger.info("ScraperStrategy: Using premium API for #{url}")
    response = @premium_client.fetch(url: url)

    # Step 4: Increment premium usage counter
    increment_premium_usage

    Rails.logger.info("ScraperStrategy: Successfully scraped #{url} using premium API")
    response.merge(strategy: "premium")
  rescue ScraperApiClient::Error => e
    Rails.logger.error("ScraperStrategy: Premium API also failed: #{e.class} - #{e.message}")
    raise Error, "Both free and premium scraping strategies failed. Last error: #{e.message}"
  end

  def check_budget!
    current_usage = get_premium_usage
    if current_usage >= @budget_limit
      raise BudgetExceededError, "Premium API budget limit (#{@budget_limit}) exceeded. Current usage: #{current_usage}"
    end
  end

  def get_premium_usage
    value = @redis.get(PREMIUM_USAGE_KEY)
    value ? value.to_i : 0
  end

  def increment_premium_usage
    @redis.incr(PREMIUM_USAGE_KEY)
  rescue Redis::BaseError => e
    Rails.logger.error("ScraperStrategy: Failed to increment premium usage counter: #{e.message}")
    # Don't fail the request if Redis is down, but log the error
  end

  def redis_client
    redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
    Redis.new(url: redis_url)
  rescue Redis::BaseError => e
    Rails.logger.error("ScraperStrategy: Failed to connect to Redis: #{e.message}")
    # Return a mock Redis client that does nothing
    # This allows the strategy to work even if Redis is down (budget tracking won't work)
    MockRedis.new
  end

  # Mock Redis client for when Redis is unavailable
  # Allows the strategy to work, but budget tracking is disabled
  class MockRedis
    def get(_key)
      "0"
    end

    def incr(_key)
      1
    end
  end
end
