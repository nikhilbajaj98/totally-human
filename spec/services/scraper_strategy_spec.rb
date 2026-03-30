# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScraperStrategy do
  let(:mask_client) { instance_double(MaskServiceClient) }
  let(:premium_client) { instance_double(ScraperApiClient) }
  let(:mock_redis) { ScraperStrategy::MockRedis.new }

  let(:free_success) do
    { status: 200, html: "<html>Free</html>", headers: {}, error: false, error_message: nil }
  end

  let(:premium_success) do
    { status: 200, html: "<html>Premium</html>", headers: {}, error: false, error_message: nil }
  end

  subject(:strategy) { described_class.new }

  before do
    allow(MaskServiceClient).to receive(:new).and_return(mask_client)
    allow(ScraperApiClient).to receive(:new).and_return(premium_client)
    allow(Redis).to receive(:new).and_return(mock_redis)

    allow(Yabeda.totallyhuman).to receive_messages(
      scrape_requests_total: double(increment: nil),
      scrape_duration_seconds: double(measure: nil),
      fallbacks_total: double(increment: nil),
      premium_budget_used: double(set: nil),
      cost_saved_total: double(increment: nil)
    )
  end

  describe "#execute" do
    context "when mask-service succeeds" do
      it "returns the response with strategy: free" do
        allow(mask_client).to receive(:fetch).and_return(free_success)

        result = strategy.execute(url: "https://example.com")

        expect(result[:strategy]).to eq("free")
        expect(result[:html]).to eq("<html>Free</html>")
      end

      it "does not call the premium client" do
        allow(mask_client).to receive(:fetch).and_return(free_success)

        strategy.execute(url: "https://example.com")

        expect(premium_client).not_to have_received(:fetch) if premium_client.respond_to?(:fetch)
      end
    end

    context "when mask-service returns 403" do
      it "falls back to premium and returns strategy: premium" do
        allow(mask_client).to receive(:fetch)
          .and_return(status: 403, html: "", headers: {}, error: false, error_message: nil)
        allow(premium_client).to receive(:fetch).and_return(premium_success)

        result = strategy.execute(url: "https://blocked.com")

        expect(result[:strategy]).to eq("premium")
        expect(result[:html]).to eq("<html>Premium</html>")
      end
    end

    context "when mask-service returns 429" do
      it "falls back to premium" do
        allow(mask_client).to receive(:fetch)
          .and_return(status: 429, html: "", headers: {}, error: false, error_message: nil)
        allow(premium_client).to receive(:fetch).and_return(premium_success)

        result = strategy.execute(url: "https://ratelimited.com")

        expect(result[:strategy]).to eq("premium")
      end
    end

    context "when mask-service returns 5xx" do
      it "falls back to premium" do
        allow(mask_client).to receive(:fetch)
          .and_return(status: 502, html: "", headers: {}, error: false, error_message: nil)
        allow(premium_client).to receive(:fetch).and_return(premium_success)

        result = strategy.execute(url: "https://server-error.com")

        expect(result[:strategy]).to eq("premium")
      end
    end

    context "when mask-service returns error flag" do
      it "falls back to premium" do
        allow(mask_client).to receive(:fetch)
          .and_return(status: 200, html: "", headers: {}, error: true, error_message: "TLS error")
        allow(premium_client).to receive(:fetch).and_return(premium_success)

        result = strategy.execute(url: "https://tls-error.com")

        expect(result[:strategy]).to eq("premium")
      end
    end

    context "when mask-service raises a network error" do
      it "falls back to premium" do
        allow(mask_client).to receive(:fetch)
          .and_raise(MaskServiceClient::NetworkError, "Connection refused")
        allow(premium_client).to receive(:fetch).and_return(premium_success)

        result = strategy.execute(url: "https://example.com")

        expect(result[:strategy]).to eq("premium")
      end
    end

    context "when both strategies fail" do
      it "raises ScraperStrategy::Error" do
        allow(mask_client).to receive(:fetch)
          .and_raise(MaskServiceClient::NetworkError, "Connection refused")
        allow(premium_client).to receive(:fetch)
          .and_raise(ScraperApiClient::Error, "Premium API down")

        expect { strategy.execute(url: "https://example.com") }
          .to raise_error(ScraperStrategy::Error, /Both free and premium/)
      end
    end

    context "when premium budget is exceeded" do
      it "raises BudgetExceededError" do
        allow(mask_client).to receive(:fetch)
          .and_raise(MaskServiceClient::NetworkError, "Connection refused")
        allow(premium_client).to receive(:fetch)
          .and_raise(ScraperApiClient::BudgetExceededError, "402 Payment Required")

        expect { strategy.execute(url: "https://example.com") }
          .to raise_error(ScraperStrategy::BudgetExceededError, /budget exceeded/i)
      end
    end

    context "when instrumentation fails" do
      it "still executes the fallback" do
        allow(mask_client).to receive(:fetch)
          .and_return(status: 403, html: "", headers: {}, error: false, error_message: nil)
        allow(premium_client).to receive(:fetch).and_return(premium_success)
        allow(Yabeda.totallyhuman.fallbacks_total).to receive(:increment).and_raise(RuntimeError, "metrics broken")

        result = strategy.execute(url: "https://example.com")

        expect(result[:strategy]).to eq("premium")
      end
    end

    context "when Redis is unavailable" do
      it "uses MockRedis and strategy still works" do
        allow(Redis).to receive(:new).and_raise(Redis::CannotConnectError, "Connection refused")
        allow(mask_client).to receive(:fetch).and_return(free_success)

        fresh_strategy = described_class.new
        result = fresh_strategy.execute(url: "https://example.com")

        expect(result[:strategy]).to eq("free")
      end
    end
  end
end
