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
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    Rails.logger.info("ScraperStrategy: Attempting free mask-service for #{url}")
    response = @mask_client.fetch(url: url, proxy: proxy)

    if should_fallback?(response)
      reason = fallback_reason(response)
      Yabeda.totallyhuman.fallbacks_total.increment({ reason: reason })
      Rails.logger.warn("ScraperStrategy: Mask service returned status #{response[:status]}, switching to premium API")
      return fallback_to_premium(url: url, start_time: start_time)
    end

    record_metrics(strategy: "free", status: "done", start_time: start_time)
    Rails.logger.info("ScraperStrategy: Successfully scraped #{url} using free mask-service")
    response.merge(strategy: "free")
  rescue MaskServiceClient::Error => e
    Yabeda.totallyhuman.fallbacks_total.increment({ reason: "network_error" })
    Rails.logger.warn("ScraperStrategy: Mask service error (#{e.class}), switching to premium API: #{e.message}")
    fallback_to_premium(url: url, start_time: start_time)
  end

  private

  def should_fallback?(response)
    return true if response[:error]
    return true if FALLBACK_STATUS_CODES.include?(response[:status])
    return true if response[:status] >= 500

    false
  end

  def fallback_reason(response)
    return "error_flag" if response[:error]

    case response[:status]
    when 403 then "status_403"
    when 429 then "status_429"
    else "status_5xx"
    end
  end

  def record_metrics(strategy:, status:, start_time:)
    Yabeda.totallyhuman.scrape_requests_total.increment({ strategy: strategy, status: status })

    if strategy == "free" && status == "done"
      Yabeda.totallyhuman.cost_saved_total.increment({})
    end

    if start_time
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      Yabeda.totallyhuman.scrape_duration_seconds.measure({ strategy: strategy }, duration)
    end

    Yabeda.totallyhuman.premium_budget_used.set({}, get_premium_usage)
  rescue => e
    Rails.logger.error("ScraperStrategy: Failed to record metrics: #{e.message}")
  end

  def fallback_to_premium(url:, start_time: nil)
    reserve_premium_slot!

    begin
      Rails.logger.info("ScraperStrategy: Using premium API for #{url}")
      response = @premium_client.fetch(url: url)

      record_metrics(strategy: "premium", status: "done", start_time: start_time)
      Rails.logger.info("ScraperStrategy: Successfully scraped #{url} using premium API")
      response.merge(strategy: "premium")
    rescue ScraperApiClient::BudgetExceededError => e
      release_premium_slot!
      record_metrics(strategy: "premium", status: "failed", start_time: start_time)
      Rails.logger.error("ScraperStrategy: Premium provider budget exceeded: #{e.message}")
      raise BudgetExceededError, "Premium provider budget exceeded: #{e.message}"
    rescue ScraperApiClient::Error => e
      release_premium_slot!
      record_metrics(strategy: "premium", status: "failed", start_time: start_time)
      Rails.logger.error("ScraperStrategy: Premium API also failed: #{e.class} - #{e.message}")
      raise Error, "Both free and premium scraping strategies failed. Last error: #{e.message}"
    end
  end

  RESERVE_SLOT_SCRIPT = <<~LUA
    local current = tonumber(redis.call('GET', KEYS[1]) or '0')
    if current >= tonumber(ARGV[1]) then
      return -1
    end
    return redis.call('INCR', KEYS[1])
  LUA

  def reserve_premium_slot!
    result = @redis.eval(RESERVE_SLOT_SCRIPT, keys: [PREMIUM_USAGE_KEY], argv: [@budget_limit])
    if result == -1
      usage = get_premium_usage
      raise BudgetExceededError,
        "Premium API budget limit (#{@budget_limit}) exceeded. Current usage: #{usage}"
    end
  rescue Redis::BaseError => e
    Rails.logger.error("ScraperStrategy: Failed to reserve premium slot: #{e.message}")
  end

  def release_premium_slot!
    @redis.decr(PREMIUM_USAGE_KEY)
  rescue Redis::BaseError => e
    Rails.logger.error("ScraperStrategy: Failed to release premium slot: #{e.message}")
  end

  def get_premium_usage
    value = @redis.get(PREMIUM_USAGE_KEY)
    value ? value.to_i : 0
  rescue Redis::BaseError => e
    Rails.logger.error("ScraperStrategy: Failed to read premium usage counter: #{e.message}")
    0
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

    def decr(_key)
      0
    end

    def eval(_script, keys: [], argv: [])
      1
    end
  end
end
