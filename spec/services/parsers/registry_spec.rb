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

    it "returns RawParser for non-Google URLs" do
      parser = described_class.for_url("https://example.com/page")

      expect(parser).to be_a(Parsers::RawParser)
    end

    it "returns RawParser for Google non-search pages" do
      parser = described_class.for_url("https://www.google.com/maps")

      expect(parser).to be_a(Parsers::RawParser)
    end
  end
end
