# frozen_string_literal: true

require "rails_helper"

RSpec.describe Parsers::Registry do
  describe ".for_url" do
    it "returns GoogleSearchParser for google.com/search URLs" do
      parser = described_class.for_url("https://www.google.com/search?q=test")

      expect(parser).to be_a(Parsers::GoogleSearchParser)
    end

    it "returns GoogleSearchParser for regional Google domains" do
      parser = described_class.for_url("https://www.google.co.uk/search?q=test")

      expect(parser).to be_a(Parsers::GoogleSearchParser)
    end

    it "returns AmazonProductParser for amazon.com /dp/ URLs" do
      url = "https://www.amazon.com/Echo-Dot-5th-Gen/dp/B0DTEST123?ref_=sr_1_1"
      parser = described_class.for_url(url)

      expect(parser).to be_a(Parsers::AmazonProductParser)
    end

    it "returns AmazonProductParser for smile.amazon.co.uk /gp/product/ URLs" do
      url = "https://smile.amazon.co.uk/gp/product/B0JKLMNOPQ/ref=sr_1"
      parser = described_class.for_url(url)

      expect(parser).to be_a(Parsers::AmazonProductParser)
    end

    it "returns AmazonSearchParser for Amazon /s? search URLs" do
      parser = described_class.for_url("https://www.amazon.com/s?k=echo+dot&crid=abc")

      expect(parser).to be_a(Parsers::AmazonSearchParser)
    end

    it "returns AmazonSearchParser for Amazon /s/ref= search URLs" do
      parser = described_class.for_url("https://www.amazon.com/s/ref=nb_sb_noss_1?url=search-alias%3Daps")

      expect(parser).to be_a(Parsers::AmazonSearchParser)
    end

    it "returns HackerNewsParser for news.ycombinator.com" do
      parser = described_class.for_url("https://news.ycombinator.com/")

      expect(parser).to be_a(Parsers::HackerNewsParser)
    end

    it "returns HackerNewsParser for HN Firebase API" do
      parser = described_class.for_url("https://hacker-news.firebaseio.com/v0/topstories.json")

      expect(parser).to be_a(Parsers::HackerNewsParser)
    end

    it "returns ArticleParser for generic URLs (default fallback)" do
      parser = described_class.for_url("https://example.com/page")

      expect(parser).to be_a(Parsers::ArticleParser)
    end

    it "returns ArticleParser for Google non-search pages" do
      parser = described_class.for_url("https://www.google.com/maps")

      expect(parser).to be_a(Parsers::ArticleParser)
    end
  end
end
