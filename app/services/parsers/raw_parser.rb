# frozen_string_literal: true

module Parsers
  class RawParser < BaseParser
    MAX_HTML_CHARS = 100_000

    def parse(html)
      { raw_html: html.to_s[0, MAX_HTML_CHARS] }
    end
  end
end
