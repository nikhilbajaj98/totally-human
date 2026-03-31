# frozen_string_literal: true

require "rails_helper"

RSpec.describe Parsers::AmazonProductParser do
  let(:parser) { described_class.new }
  let(:html) { File.read(Rails.root.join("spec/fixtures/parsers/amazon_product.html")) }

  describe "#parse" do
    subject(:result) { parser.parse(html) }

    it "extracts ASIN from canonical URL" do
      expect(result[:asin]).to eq("B0TESTPROD")
    end

    it "extracts the product title" do
      expect(result[:title]).to include("Echo Dot")
      expect(result[:title]).to include("5th Gen")
    end

    it "extracts the display price" do
      expect(result[:price]).to eq("$49.99")
    end

    it "extracts the star rating" do
      expect(result[:rating]).to eq(4.6)
    end

    it "extracts the review count" do
      expect(result[:review_count]).to eq(12_347)
    end

    it "extracts availability text" do
      expect(result[:availability]).to match(/in stock/i)
    end

    it "collects image URLs from landing image and JSON" do
      expect(result[:images]).to include("https://m.media-amazon.com/images/I/71landing-main.jpg")
      expect(result[:images]).to include("https://m.media-amazon.com/images/I/81alt-thumb.jpg")
      expect(result[:images]).to include("https://m.media-amazon.com/images/I/81og-primary.jpg")
    end

    it "extracts feature bullets" do
      expect(result[:features].length).to eq(3)
      expect(result[:features]).to include("Our most popular smart speaker with Alexa")
      expect(result[:features]).to include("Voice control for music, news, and compatible smart home")
    end
  end

  describe "fallback selectors" do
    it "parses rating from a-icon-alt when popover title is missing" do
      minimal = <<~HTML
        <html><body>
          <span id="productTitle">Minimal Widget</span>
          <i class="a-icon a-icon-star a-star-4"><span class="a-icon-alt">4.0 out of 5 stars</span></i>
          <span id="acrCustomerReviewText">99 ratings</span>
        </body></html>
      HTML
      result = parser.parse(minimal)
      expect(result[:rating]).to eq(4.0)
      expect(result[:review_count]).to eq(99)
    end

    it "parses whole-number ratings from title and star strings" do
      expect(parser.send(:parse_rating_from_string, "4 out of 5 stars")).to eq(4.0)
      expect(parser.send(:parse_rating_from_string, "3 stars")).to eq(3.0)
    end

    it "builds price from whole + fraction when offscreen is absent" do
      fragment = <<~HTML
        <html><body>
          <span id="productTitle">Widget</span>
          <span class="a-price-symbol">$</span>
          <span class="a-price-whole">29</span>
          <span class="a-price-fraction">99</span>
        </body></html>
      HTML
      result = parser.parse(fragment)
      expect(result[:price]).to eq("$29.99")
    end
  end

  describe "#safe_parse" do
    it "returns error hash when parse raises" do
      allow(parser).to receive(:parse).and_raise(StandardError, "boom")
      result = parser.safe_parse("<html></html>")
      expect(result[:error]).to be true
      expect(result[:error_message]).to include("boom")
    end
  end
end
