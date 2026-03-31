# frozen_string_literal: true

module Parsers
  class GoogleSearchParser < BaseParser
    CAPTCHA_INDICATORS = [ "unusual traffic", "captcha", "recaptcha", "sorry/index" ].freeze

    def parse(html)
      return { captcha: true, organic_results: [], related_searches: [], search_metadata: {} } if captcha?(html)

      document = doc(html)

      {
        organic_results: extract_organic_results(document),
        related_searches: extract_related_searches(document),
        search_metadata: extract_search_metadata(document)
      }
    end

    private

    def captcha?(html)
      lower = html.to_s.downcase
      CAPTCHA_INDICATORS.any? { |indicator| lower.include?(indicator) }
    end

    def extract_organic_results(document)
      results = []

      document.css("div.g").each_with_index do |result_node, index|
        title_node = result_node.at_css("h3")
        next unless title_node

        link_node = result_node.at_css("a[href]")
        href = link_node&.[]("href")
        next if href.nil? || href.start_with?("#") || href.start_with?("/search")

        snippet = extract_snippet(result_node)
        displayed_link = extract_displayed_link(result_node)

        results << {
          position: results.size + 1,
          title: text(title_node),
          link: href,
          snippet: snippet,
          displayed_link: displayed_link
        }
      end

      results
    end

    def extract_snippet(result_node)
      snippet_selectors = [
        "div.VwiC3b",
        "div[data-sncf]",
        "div.IsZvec",
        "span.aCOpRe"
      ]

      snippet_selectors.each do |selector|
        node = result_node.at_css(selector)
        result = clean_text(text(node))
        return result if result
      end

      nil
    end

    def extract_displayed_link(result_node)
      cite_node = result_node.at_css("cite")
      text(cite_node)
    end

    def extract_related_searches(document)
      searches = []

      document.css("div.s75CSd a, a.k8XOCe").each do |link|
        term = clean_text(text(link))
        searches << term if term && !term.empty?
      end

      searches.uniq
    end

    def extract_search_metadata(document)
      metadata = {}

      stats_node = document.at_css("div#result-stats")
      if stats_node
        stats_text = text(stats_node)
        if stats_text
          total_match = stats_text.match(/About ([\d,]+) results/)
          metadata[:total_results] = total_match[1].delete(",").to_i if total_match

          time_match = stats_text.match(/\(([\d.]+) seconds\)/)
          metadata[:time_taken] = time_match[1].to_f if time_match
        end
      end

      title_node = document.at_css("title")
      if title_node
        title_text = text(title_node)
        query_match = title_text&.match(/(.+?)\s*-\s*Google/)
        metadata[:query] = query_match[1].strip if query_match
      end

      metadata
    end
  end
end
