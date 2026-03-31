# frozen_string_literal: true

require "rails_helper"

RSpec.describe Parsers::ArticleParser do
  let(:parser) { described_class.new }
  let(:html) { File.read(Rails.root.join("spec/fixtures/parsers/article.html")) }

  describe "#parse" do
    subject(:result) { parser.parse(html) }

    it "extracts the title from og:title" do
      expect(result[:title]).to eq("The Future of Web Scraping")
    end

    it "extracts the author from meta tag" do
      expect(result[:author]).to eq("Jane Doe")
    end

    it "extracts the published date" do
      expect(result[:published_date]).to eq("2025-06-15T09:00:00Z")
    end

    it "extracts the description from og:description" do
      expect(result[:description]).to include("in-depth look")
    end

    it "extracts body text from article paragraphs" do
      expect(result[:body_text]).to include("Web scraping has come a long way")
      expect(result[:body_text]).to include("curl_cffi")
    end

    it "strips script and style tags from body" do
      expect(result[:body_text]).not_to include("console.log")
      expect(result[:body_text]).not_to include(".hidden")
    end

    it "calculates word count" do
      expect(result[:word_count]).to be > 50
    end

    it "extracts the language" do
      expect(result[:language]).to eq("en")
    end
  end

  describe "fallback behavior" do
    it "extracts title from h1 when no og:title" do
      simple_html = "<html><body><h1>My Title</h1><p>Content here.</p></body></html>"
      result = parser.parse(simple_html)
      expect(result[:title]).to eq("My Title")
    end

    it "extracts title from title tag as last resort" do
      simple_html = "<html><head><title>Page Title</title></head><body><p>Content.</p></body></html>"
      result = parser.parse(simple_html)
      expect(result[:title]).to eq("Page Title")
    end

    it "handles minimal HTML gracefully" do
      result = parser.parse("<html><body></body></html>")
      expect(result[:title]).to be_nil
      expect(result[:author]).to be_nil
      expect(result[:word_count]).to eq(0)
    end
  end

  describe "#safe_parse" do
    it "catches errors and returns error hash" do
      allow(parser).to receive(:parse).and_raise(StandardError, "boom")
      result = parser.safe_parse("<html></html>")
      expect(result[:error]).to be true
      expect(result[:error_message]).to include("boom")
    end
  end
end
