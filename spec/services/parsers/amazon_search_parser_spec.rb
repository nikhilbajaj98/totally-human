# frozen_string_literal: true

require "rails_helper"

RSpec.describe Parsers::AmazonSearchParser do
  let(:parser) { described_class.new }
  let(:html) { File.read(Rails.root.join("spec/fixtures/parsers/amazon_search.html")) }

  describe "#parse" do
    subject(:result) { parser.parse(html) }

    it "extracts product cards with ASIN and title" do
      expect(result[:products].length).to eq(3)

      first = result[:products].find { |p| p[:asin] == "B0SRCHAAA1" }
      expect(first[:title]).to include("COSORI Pro Air Fryer")
      expect(first[:url]).to start_with("https://www.amazon.com/")
      expect(first[:price]).to eq("$89.99")
      expect(first[:rating]).to eq(4.5)
      expect(first[:review_count]).to eq(12_345)
      expect(first[:image_url]).to include("media-amazon.com")
      expect(first[:is_sponsored]).to be false
    end

    it "marks sponsored results" do
      sponsored = result[:products].find { |p| p[:asin] == "B0SRCHAAA2" }
      expect(sponsored[:is_sponsored]).to be true
      expect(sponsored[:title]).to include("Sponsored Ninja")
    end

    it "assigns sequential positions" do
      positions = result[:products].map { |p| p[:position] }
      expect(positions).to eq([ 1, 2, 3 ])
    end

    it "parses integer star ratings from a-icon-alt" do
      third = result[:products].find { |p| p[:asin] == "B0SRCHAAA3" }
      expect(third[:rating]).to eq(4.0)
      expect(third[:review_count]).to eq(8888)
    end

    it "includes search metadata when present" do
      expect(result[:search_metadata][:results_info]).to include("9,000 results")
    end
  end

  describe "robot / captcha pages" do
    it "raises RobotDetectedError so callers can fail the job" do
      page = "<html><body>Sorry! We just need to make sure you're not a robot</body></html>"
      expect { parser.parse(page) }.to raise_error(Parsers::RobotDetectedError, /robot/i)
    end
  end

  describe "#absolutize_amazon_url" do
    it "uses the source URL host for relative paths" do
      uk = described_class.new(source_url: "https://www.amazon.co.uk/s?k=test")
      expect(uk.send(:absolutize_amazon_url, "/dp/B012345678")).to eq("https://www.amazon.co.uk/dp/B012345678")
    end
  end

  describe "#safe_parse" do
    it "returns error hash when parse raises" do
      allow(parser).to receive(:parse).and_raise(StandardError, "boom")
      result = parser.safe_parse("<html></html>")
      expect(result[:error]).to be true
    end
  end
end
