# frozen_string_literal: true

require "redis"

# Redis-based rate limiter providing per-domain and global concurrency control.
# Uses atomic Lua scripts to safely acquire/release slots in a multi-worker environment.
# Slots auto-expire (TTL safety net) in case a worker crashes without calling release!.
class RateLimiter
  class LimitExceeded < StandardError; end

  DOMAIN_KEY_PREFIX = "totallyhuman:ratelimit:domain:"
  GLOBAL_KEY = "totallyhuman:ratelimit:global"
  SLOT_TTL_SECONDS = 120

  def initialize(redis: nil)
    @redis = redis || redis_client
    @per_domain_limit = ENV.fetch("RATE_LIMIT_PER_DOMAIN", 2).to_i
    @global_limit = ENV.fetch("MAX_CONCURRENT_SCRAPES", 10).to_i
  end

  # Attempt to acquire a slot for the given domain.
  # Returns true if both per-domain and global limits allow it, false otherwise.
  def acquire!(domain)
    domain_key = domain_key_for(domain)

    result = @redis.eval(
      ACQUIRE_SCRIPT,
      keys: [ domain_key, GLOBAL_KEY ],
      argv: [ @per_domain_limit, @global_limit, SLOT_TTL_SECONDS ]
    )

    result == 1
  rescue Redis::BaseError => e
    Rails.logger.error("RateLimiter: Redis error on acquire: #{e.message}")
    true
  end

  # Release a slot for the given domain. Must be called in an ensure block.
  def release!(domain)
    domain_key = domain_key_for(domain)

    @redis.eval(
      RELEASE_SCRIPT,
      keys: [ domain_key, GLOBAL_KEY ]
    )
  rescue Redis::BaseError => e
    Rails.logger.error("RateLimiter: Redis error on release: #{e.message}")
  end

  # Current concurrency count for a domain (for observability / testing)
  def domain_usage(domain)
    value = @redis.get(domain_key_for(domain))
    value ? value.to_i : 0
  rescue Redis::BaseError
    0
  end

  # Current global concurrency count (for observability / testing)
  def global_usage
    value = @redis.get(GLOBAL_KEY)
    value ? value.to_i : 0
  rescue Redis::BaseError
    0
  end

  private

  def domain_key_for(domain)
    "#{DOMAIN_KEY_PREFIX}#{domain}"
  end

  def redis_client
    redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
    Redis.new(url: redis_url)
  rescue Redis::BaseError => e
    Rails.logger.error("RateLimiter: Failed to connect to Redis: #{e.message}")
    ScraperStrategy::MockRedis.new
  end

  # Atomically check both limits and increment if within bounds.
  # Returns 1 on success, 0 if per-domain limit hit, -1 if global limit hit.
  ACQUIRE_SCRIPT = <<~LUA
    local domain_key   = KEYS[1]
    local global_key   = KEYS[2]
    local domain_limit = tonumber(ARGV[1])
    local global_limit = tonumber(ARGV[2])
    local ttl          = tonumber(ARGV[3])

    local domain_current = tonumber(redis.call('GET', domain_key) or '0')
    if domain_current >= domain_limit then
      return 0
    end

    local global_current = tonumber(redis.call('GET', global_key) or '0')
    if global_current >= global_limit then
      return -1
    end

    redis.call('INCR', domain_key)
    redis.call('EXPIRE', domain_key, ttl)
    redis.call('INCR', global_key)
    redis.call('EXPIRE', global_key, ttl)
    return 1
  LUA

  # Atomically decrement both counters, flooring at 0.
  RELEASE_SCRIPT = <<~LUA
    local domain_key = KEYS[1]
    local global_key = KEYS[2]

    local d = tonumber(redis.call('GET', domain_key) or '0')
    if d > 0 then
      redis.call('DECR', domain_key)
    end

    local g = tonumber(redis.call('GET', global_key) or '0')
    if g > 0 then
      redis.call('DECR', global_key)
    end
  LUA
end
