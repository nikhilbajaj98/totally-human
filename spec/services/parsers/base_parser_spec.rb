# frozen_string_literal: true

require "rails_helper"

RSpec.describe Parsers::BaseParser do
  subject(:parser) { described_class.new }

  describe "#parse" do
    it "raises NotImplementedError" do
      expect { parser.parse("<html></html>") }
        .to raise_error(NotImplementedError, /must be implemented/)
    end
  end

  describe "#safe_parse" do
    it "wraps parsing errors and returns an error hash" do
      result = parser.safe_parse("<html></html>")

      expect(result[:error]).to be true
      expect(result[:error_message]).to include("must be implemented")
    end

    it "returns the parsed result when parsing succeeds" do
      allow(parser).to receive(:parse).and_return({ test: true })

      result = parser.safe_parse("<html></html>")

      expect(result[:test]).to be true
    end

    it "re-raises RobotDetectedError so workers can mark jobs failed" do
      allow(parser).to receive(:parse).and_raise(Parsers::RobotDetectedError, "blocked")

      expect { parser.safe_parse("<html></html>") }.to raise_error(Parsers::RobotDetectedError, "blocked")
    end
  end
end
