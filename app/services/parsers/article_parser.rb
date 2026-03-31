# frozen_string_literal: true

module Parsers
  # Generic article parser that attempts to extract structured data from any webpage.
  # Uses common HTML patterns and meta tags to find title, author, date, and body text.
  # Designed as the default fallback parser (replaces RawParser) to always return
  # something useful rather than raw HTML.
  class ArticleParser < BaseParser
    MAX_BODY_CHARS = 50_000

    def parse(html)
      document = doc(html)

      {
        title: extract_title(document),
        author: extract_author(document),
        published_date: extract_date(document),
        description: extract_description(document),
        body_text: extract_body(document),
        word_count: extract_body(document)&.split(/\s+/)&.size || 0,
        language: extract_language(document)
      }
    end

    private

    def extract_title(document)
      og_title = meta_content(document, "og:title")
      return og_title if og_title

      twitter_title = meta_content(document, "twitter:title")
      return twitter_title if twitter_title

      h1 = document.at_css("article h1") || document.at_css("h1")
      return clean_text(text(h1)) if h1

      title_tag = document.at_css("title")
      clean_text(text(title_tag))
    end

    def extract_author(document)
      meta_content(document, "author") ||
        meta_content(document, "article:author") ||
        meta_content(document, "dc.creator") ||
        extract_ld_json_field(document, "author") ||
        extract_byline(document)
    end

    def extract_date(document)
      meta_content(document, "article:published_time") ||
        meta_content(document, "datePublished") ||
        meta_content(document, "dc.date") ||
        extract_ld_json_field(document, "datePublished") ||
        extract_time_element(document)
    end

    def extract_description(document)
      meta_content(document, "og:description") ||
        meta_content(document, "description") ||
        meta_content(document, "twitter:description")
    end

    def extract_body(document)
      @body_text ||= begin
        article_node = document.at_css("article") ||
                       document.at_css("[role='main']") ||
                       document.at_css("main") ||
                       document.at_css(".post-content") ||
                       document.at_css(".entry-content") ||
                       document.at_css(".article-body") ||
                       document.at_css("#content") ||
                       document.at_css("body")

        return nil unless article_node

        article_node.css("script, style, nav, header, footer, aside, iframe, noscript").each(&:remove)

        paragraphs = article_node.css("p").map { |p| clean_text(text(p)) }.compact
        body = paragraphs.join("\n\n")
        body = body[0, MAX_BODY_CHARS] if body.length > MAX_BODY_CHARS
        body.presence
      end
    end

    def extract_language(document)
      document.at_css("html")&.[]("lang")&.strip&.presence
    end

    def meta_content(document, name)
      node = document.at_css("meta[property='#{name}']") ||
             document.at_css("meta[name='#{name}']") ||
             document.at_css("meta[itemprop='#{name}']")
      value = node&.[]("content")
      value&.strip&.presence
    end

    def extract_ld_json_field(document, field)
      document.css("script[type='application/ld+json']").each do |script|
        data = JSON.parse(text(script) || "")
        value = data[field]
        return value.is_a?(Hash) ? value["name"] : value.to_s if value.present?
      rescue JSON::ParserError
        next
      end
      nil
    end

    def extract_byline(document)
      selectors = [ ".byline", ".author", "[rel='author']", ".post-author", ".article-author" ]
      selectors.each do |selector|
        node = document.at_css(selector)
        result = clean_text(text(node))
        return result if result
      end
      nil
    end

    def extract_time_element(document)
      time_node = document.at_css("article time[datetime]") || document.at_css("time[datetime]")
      time_node&.[]("datetime")&.strip&.presence
    end
  end
end
