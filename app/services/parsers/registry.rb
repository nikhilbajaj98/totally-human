# frozen_string_literal: true

module Parsers
  class Registry
    PARSERS = [
      [ /google\.(com|co\.\w+)\/search/, GoogleSearchParser ]
    ].freeze

    def self.for_url(url)
      PARSERS.each do |pattern, parser_class|
        return parser_class.new if url.match?(pattern)
      end

      RawParser.new
    end
  end
end
