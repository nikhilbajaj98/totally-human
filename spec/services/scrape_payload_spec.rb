# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScrapePayload do
  describe ".utf8" do
    it "passes through valid UTF-8 strings" do
      expect(described_class.utf8("café")).to eq("café")
    end

    it "scrubs invalid UTF-8 byte sequences in strings" do
      bad = (+"hello").b + "\xC3".b + "world".b
      result = described_class.utf8(bad)
      expect(result.valid_encoding?).to be true
      expect(result.encoding).to eq(Encoding::UTF_8)
      expect(result).to include("hello")
    end

    it "recursively normalizes hashes and arrays" do
      bad_html = (+"\xC3\x28").b # invalid sequence
      input = {
        html: bad_html,
        nested: { "h" => [ "ok", bad_html ] },
        num: 200
      }
      out = described_class.utf8(input)
      expect(out[:html].valid_encoding?).to be true
      expect(out[:nested]["h"][1].valid_encoding?).to be true
      expect(out[:num]).to eq(200)
    end
  end
end
