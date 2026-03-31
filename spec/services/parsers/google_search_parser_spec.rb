# frozen_string_literal: true

require "rails_helper"

RSpec.describe Parsers::GoogleSearchParser do
  subject(:parser) { described_class.new }

  let(:fixture_path) { Rails.root.join("spec/fixtures/parsers") }

  describe "#parse" do
    context "with a standard search results page" do
      let(:html) { File.read(fixture_path.join("google_search.html")) }

      it "extracts organic results" do
        result = parser.parse(html)

        expect(result[:organic_results]).to be_an(Array)
        expect(result[:organic_results].length).to eq(5)
      end

      it "extracts title, link, and snippet for each result" do
        result = parser.parse(html)
        first = result[:organic_results].first

        expect(first[:position]).to eq(1)
        expect(first[:title]).to eq("The 20 Best Coffee Shops in NYC")
        expect(first[:link]).to eq("https://www.eater.com/maps/best-coffee-shops-nyc")
        expect(first[:snippet]).to include("classic diners to specialty roasters")
      end

      it "extracts displayed_link from cite element" do
        result = parser.parse(html)
        first = result[:organic_results].first

        expect(first[:displayed_link]).to include("eater.com")
      end

      it "assigns sequential positions" do
        result = parser.parse(html)
        positions = result[:organic_results].map { |r| r[:position] }

        expect(positions).to eq([ 1, 2, 3, 4, 5 ])
      end

      it "extracts related searches" do
        result = parser.parse(html)

        expect(result[:related_searches]).to be_an(Array)
        expect(result[:related_searches]).to include("best espresso nyc")
        expect(result[:related_searches]).to include("best cold brew nyc")
        expect(result[:related_searches]).to include("specialty coffee manhattan")
      end

      it "extracts search metadata" do
        result = parser.parse(html)

        expect(result[:search_metadata][:total_results]).to eq(142_000_000)
        expect(result[:search_metadata][:time_taken]).to eq(0.52)
        expect(result[:search_metadata][:query]).to eq("best coffee nyc")
      end
    end

    context "with a CAPTCHA page" do
      let(:html) { File.read(fixture_path.join("google_search_captcha.html")) }

      it "detects the CAPTCHA" do
        result = parser.parse(html)

        expect(result[:captcha]).to be true
        expect(result[:organic_results]).to eq([])
      end
    end

    context "with a no-results page" do
      let(:html) { File.read(fixture_path.join("google_search_no_results.html")) }

      it "returns empty organic results" do
        result = parser.parse(html)

        expect(result[:organic_results]).to eq([])
      end
    end

    context "with empty HTML" do
      it "returns empty results without raising" do
        result = parser.parse("")

        expect(result[:organic_results]).to eq([])
        expect(result[:related_searches]).to eq([])
      end
    end
  end

  describe "#safe_parse" do
    it "returns error hash if parsing fails internally" do
      allow(parser).to receive(:parse).and_raise(RuntimeError, "unexpected")

      result = parser.safe_parse("<html></html>")

      expect(result[:error]).to be true
      expect(result[:error_message]).to include("unexpected")
    end
  end
end
