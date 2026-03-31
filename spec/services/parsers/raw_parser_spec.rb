# frozen_string_literal: true

require "rails_helper"

RSpec.describe Parsers::RawParser do
  subject(:parser) { described_class.new }

  describe "#parse" do
    it "returns the HTML under :raw_html" do
      result = parser.parse("<html><body>Hello</body></html>")

      expect(result[:raw_html]).to eq("<html><body>Hello</body></html>")
    end

    it "truncates HTML longer than MAX_HTML_CHARS" do
      long_html = "x" * 200_000
      result = parser.parse(long_html)

      expect(result[:raw_html].length).to eq(described_class::MAX_HTML_CHARS)
    end

    it "handles nil input gracefully" do
      result = parser.parse(nil)

      expect(result[:raw_html]).to eq("")
    end
  end
end
