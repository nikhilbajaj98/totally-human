# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateLimiter do
  let(:mock_redis) { MockRedis.new }
  let(:limiter) { described_class.new(redis: mock_redis) }

  before do
    stub_const("ENV", ENV.to_hash.merge(
      "RATE_LIMIT_PER_DOMAIN" => "2",
      "MAX_CONCURRENT_SCRAPES" => "3"
    ))
  end

  describe "#acquire!" do
    it "returns true when within limits" do
      expect(limiter.acquire!("example.com")).to be true
    end

    it "returns false when per-domain limit is reached" do
      2.times { limiter.acquire!("example.com") }

      expect(limiter.acquire!("example.com")).to be false
    end

    it "allows different domains independently" do
      2.times { limiter.acquire!("example.com") }

      expect(limiter.acquire!("other.com")).to be true
    end

    it "returns false when global limit is reached" do
      limiter.acquire!("a.com")
      limiter.acquire!("b.com")
      limiter.acquire!("c.com")

      expect(limiter.acquire!("d.com")).to be false
    end
  end

  describe "#release!" do
    it "frees a slot so another acquire succeeds" do
      2.times { limiter.acquire!("example.com") }
      expect(limiter.acquire!("example.com")).to be false

      limiter.release!("example.com")
      expect(limiter.acquire!("example.com")).to be true
    end

    it "does not decrement below zero" do
      limiter.release!("example.com")
      expect(limiter.domain_usage("example.com")).to eq(0)
    end
  end

  describe "#domain_usage" do
    it "returns 0 for unknown domain" do
      expect(limiter.domain_usage("unknown.com")).to eq(0)
    end

    it "reflects acquired slots" do
      limiter.acquire!("example.com")
      expect(limiter.domain_usage("example.com")).to eq(1)
    end
  end

  describe "#global_usage" do
    it "returns 0 when idle" do
      expect(limiter.global_usage).to eq(0)
    end

    it "reflects total acquired slots across domains" do
      limiter.acquire!("a.com")
      limiter.acquire!("b.com")
      expect(limiter.global_usage).to eq(2)
    end
  end
end

# Minimal Redis-compatible mock for testing (supports the Lua script semantics)
class MockRedis
  def initialize
    @store = {}
  end

  def get(key)
    @store[key]&.to_s
  end

  def eval(script, keys: [], argv: [])
    if script.include?("INCR")
      if keys.length == 2 && argv.length == 3
        # ACQUIRE script
        domain_key = keys[0]
        global_key = keys[1]
        domain_limit = argv[0].to_i
        global_limit = argv[1].to_i

        domain_current = (@store[domain_key] || 0).to_i
        return 0 if domain_current >= domain_limit

        global_current = (@store[global_key] || 0).to_i
        return -1 if global_current >= global_limit

        @store[domain_key] = domain_current + 1
        @store[global_key] = global_current + 1
        1
      end
    else
      # RELEASE script
      domain_key = keys[0]
      global_key = keys[1]

      d = (@store[domain_key] || 0).to_i
      @store[domain_key] = d - 1 if d > 0

      g = (@store[global_key] || 0).to_i
      @store[global_key] = g - 1 if g > 0
    end
  end
end
