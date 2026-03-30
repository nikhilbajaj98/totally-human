# frozen_string_literal: true

require "rails_helper"

RSpec.describe MaskServiceClient do
  subject(:client) { described_class.new(timeout: 5) }

  let(:mask_url) { "#{described_class::MASK_SERVICE_URL}/v1/request" }

  let(:success_body) do
    {
      status: 200,
      html: "<html><body>OK</body></html>",
      headers: { "content-type" => "text/html" },
      error: false,
      error_message: nil
    }.to_json
  end

  describe "#fetch" do
    it "returns parsed response on success" do
      stub_request(:post, mask_url)
        .with(body: { url: "https://example.com" }.to_json)
        .to_return(status: 200, body: success_body, headers: { "Content-Type" => "application/json" })

      result = client.fetch(url: "https://example.com")

      expect(result[:status]).to eq(200)
      expect(result[:html]).to include("OK")
      expect(result[:error]).to be false
    end

    it "forwards the proxy parameter in the request body" do
      stub_request(:post, mask_url)
        .with(body: { url: "https://example.com", proxy: "http://proxy:8080" }.to_json)
        .to_return(status: 200, body: success_body, headers: { "Content-Type" => "application/json" })

      client.fetch(url: "https://example.com", proxy: "http://proxy:8080")

      expect(WebMock).to have_requested(:post, mask_url)
        .with(body: hash_including("proxy" => "http://proxy:8080"))
    end

    it "omits proxy from request body when nil" do
      stub_request(:post, mask_url)
        .to_return(status: 200, body: success_body, headers: { "Content-Type" => "application/json" })

      client.fetch(url: "https://example.com")

      expect(WebMock).to have_requested(:post, mask_url)
        .with { |req| !JSON.parse(req.body).key?("proxy") }
    end

    it "returns error fields when mask-service reports an error" do
      error_body = { status: 403, html: "", headers: {}, error: true, error_message: "Forbidden" }.to_json
      stub_request(:post, mask_url)
        .to_return(status: 200, body: error_body, headers: { "Content-Type" => "application/json" })

      result = client.fetch(url: "https://blocked-site.com")

      expect(result[:status]).to eq(403)
      expect(result[:error]).to be true
      expect(result[:error_message]).to eq("Forbidden")
    end

    it "raises TimeoutError on read timeout" do
      stub_request(:post, mask_url).to_timeout

      expect { client.fetch(url: "https://example.com") }
        .to raise_error(MaskServiceClient::TimeoutError, /timed out/)
    end

    it "raises NetworkError when connection is refused" do
      stub_request(:post, mask_url).to_raise(Errno::ECONNREFUSED)

      expect { client.fetch(url: "https://example.com") }
        .to raise_error(MaskServiceClient::NetworkError, /Failed to connect/)
    end

    it "raises an error on malformed JSON" do
      stub_request(:post, mask_url)
        .to_return(status: 200, body: "not json", headers: { "Content-Type" => "text/plain" })

      expect { client.fetch(url: "https://example.com") }
        .to raise_error(MaskServiceClient::Error, /parse response body/)
    end
  end
end
