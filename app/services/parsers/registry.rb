# frozen_string_literal: true

module Parsers
  # Maps URL patterns to specialized parsers.
  # Falls back to ArticleParser for any unrecognized URL, ensuring structured
  # output (title, body, meta) rather than raw HTML in the default case.
  class Registry
    # Amazon PDP: /dp/ASIN or /gp/product/ASIN (optional slug segments). Smile +intl hosts.
    AMAZON_PDP_PATTERN = %r{
                            https?://(?:www|smile)\.amazon\.[a-z.]+
                            (?:/[\w%+.~-]+)*
                            /(?:dp|gp/product)/[A-Z0-9]{10}
                          }ix.freeze

    # Search: /s?k=…, /s/ref=nb_sb…, etc. (after PDP so product URLs stay on AmazonProductParser.)
    AMAZON_SEARCH_PATTERN = %r{
                                 https?://(?:www|smile)\.amazon\.[a-z.]+
                                 /s(?:\?|/ref=)
                               }ix.freeze

    PARSERS = [
      [ /google\.(com|co\.\w+)\/search/, GoogleSearchParser ],
      [ AMAZON_PDP_PATTERN, AmazonProductParser ],
      [ AMAZON_SEARCH_PATTERN, AmazonSearchParser ],
      [ /news\.ycombinator\.com/, HackerNewsParser ],
      [ /hacker-news\.firebaseio\.com/, HackerNewsParser ]
    ].freeze

    def self.for_url(url)
      PARSERS.each do |pattern, parser_class|
        return parser_class.new(source_url: url) if url.match?(pattern)
      end

      ArticleParser.new(source_url: url)
    end
  end
end
