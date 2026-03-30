# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScraperApiClient do
  subject(:client) { described_class.new(timeout: 5) }

  let(:api_url) { described_class::SCRAPER_API_URL }

  before do
    ENV["SCRAPINGBEE_API_KEY"] = "test_api_key_123"
  end

  after do
    ENV.delete("SCRAPINGBEE_API_KEY")
  end

  describe "#fetch" do
    it "returns parsed response on success" do
      stub_request(:get, /scrapingbee\.com/)
        .to_return(status: 200, body: "<html>OK</html>", headers: { "Content-Type" => "text/html" })

      result = client.fetch(url: "https://example.com")

      expect(result[:status]).to eq(200)
      expect(result[:html]).to eq("<html>OK</html>")
      expect(result[:error]).to be false
    end

    it "passes api_key and url as query parameters" do
      stub_request(:get, /scrapingbee\.com/)
        .to_return(status: 200, body: "OK", headers: {})

      client.fetch(url: "https://example.com")

      expect(WebMock).to have_requested(:get, /scrapingbee\.com/)
        .with(query: hash_including("api_key" => "test_api_key_123", "url" => "https://example.com"))
    end

    it "raises ConfigurationError when API key is missing" do
      ENV.delete("SCRAPINGBEE_API_KEY")
      allow(Rails.application.credentials).to receive(:scrapingbee_api_key).and_return(nil)

      expect { client.fetch(url: "https://example.com") }
        .to raise_error(ScraperApiClient::Error, /configuration error/i)
    end

    it "does not raise at initialization when API key is missing (lazy load)" do
      ENV.delete("SCRAPINGBEE_API_KEY")

      expect { described_class.new }.not_to raise_error
    end

    it "raises BudgetExceededError on HTTP 402" do
      stub_request(:get, /scrapingbee\.com/)
        .to_return(status: 402, body: "Payment required")

      expect { client.fetch(url: "https://example.com") }
        .to raise_error(ScraperApiClient::BudgetExceededError, /budget exceeded/i)
    end

    it "returns error hash for 4xx responses (non-402)" do
      stub_request(:get, /scrapingbee\.com/)
        .to_return(status: 401, body: "Unauthorized")

      result = client.fetch(url: "https://example.com")

      expect(result[:status]).to eq(401)
      expect(result[:error]).to be true
      expect(result[:error_message]).to eq("Unauthorized")
    end

    it "raises TimeoutError on read timeout" do
      stub_request(:get, /scrapingbee\.com/).to_timeout

      expect { client.fetch(url: "https://example.com") }
        .to raise_error(ScraperApiClient::TimeoutError, /timed out/)
    end

    it "raises NetworkError when connection is refused" do
      stub_request(:get, /scrapingbee\.com/).to_raise(Errno::ECONNREFUSED)

      expect { client.fetch(url: "https://example.com") }
        .to raise_error(ScraperApiClient::NetworkError, /Failed to connect/)
    end
  end
end
