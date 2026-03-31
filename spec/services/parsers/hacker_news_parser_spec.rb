# frozen_string_literal: true

require "rails_helper"

RSpec.describe Parsers::HackerNewsParser do
  let(:parser) { described_class.new }
  let(:html) { File.read(Rails.root.join("spec/fixtures/parsers/hacker_news.html")) }

  describe "#parse" do
    subject(:result) { parser.parse(html) }

    it "extracts stories from the page" do
      expect(result[:stories].length).to eq(3)
    end

    it "extracts the first story title" do
      expect(result[:stories].first[:title]).to eq("Show HN: My Cool Project")
    end

    it "extracts story URLs" do
      expect(result[:stories].first[:url]).to eq("https://example.com/article-one")
    end

    it "extracts the site domain" do
      expect(result[:stories].first[:site]).to eq("example.com")
    end

    it "extracts the score" do
      expect(result[:stories].first[:score]).to eq(142)
    end

    it "extracts the author" do
      expect(result[:stories].first[:author]).to eq("alice")
    end

    it "extracts the comment count" do
      expect(result[:stories].first[:comments_count]).to eq(87)
    end

    it "extracts the HN item id" do
      expect(result[:stories].first[:hn_id]).to eq("12345")
    end

    it "assigns sequential position numbers" do
      positions = result[:stories].map { |s| s[:position] }
      expect(positions).to eq([ 1, 2, 3 ])
    end

    it "detects more pages" do
      expect(result[:page_metadata][:has_more]).to be true
    end

    it "detects when there are no more pages" do
      html_without_more = html.gsub(/<a class="morelink"[^>]*>More<\/a>/, "")
      result_no_more = parser.parse(html_without_more)
      expect(result_no_more[:page_metadata][:has_more]).to be false
    end
  end

  describe "#safe_parse" do
    it "returns error hash on invalid HTML" do
      result = parser.safe_parse(nil)
      expect(result[:stories]).to be_empty
    end
  end
end
