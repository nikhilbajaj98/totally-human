# frozen_string_literal: true

module Parsers
  # Parses Amazon product detail pages (PDP) into structured fields.
  # Selectors follow common Amazon DOM patterns; live pages vary by A/B tests and locale.
  class AmazonProductParser < BaseParser
    ASIN_PATTERN = /\A(?<asin>[A-Z0-9]{10})\z/.freeze
    RATING_NUM = /(\d+(?:[.,]\d+)?)/.freeze

    def parse(html)
      document = doc(html)

      {
        asin: extract_asin(document),
        title: extract_title(document),
        price: extract_price(document),
        rating: extract_rating(document),
        review_count: extract_review_count(document),
        availability: extract_availability(document),
        images: extract_images(document),
        features: extract_features(document),
        brand: extract_brand(document)
      }
    end

    private

    def extract_asin(document)
      url_asin = document.at_css("link[rel='canonical']")&.[]("href")&.match(%r{/(?:dp|gp/product)/([A-Z0-9]{10})}i)&.captures&.first
      return url_asin if url_asin

      data_asin = document.at_css("#ASIN")&.[]("value") ||
                  document.at_css("input[name='ASIN.0']")&.[]("value")
      return data_asin if data_asin&.match?(ASIN_PATTERN)

      og_url = meta_content(document, "og:url")
      og_url&.match(%r{/(?:dp|gp/product)/([A-Z0-9]{10})}i)&.captures&.first
    end

    def extract_title(document)
      node = document.at_css("#productTitle") ||
             document.at_css("h1#title") ||
             document.at_css("span#productTitle") ||
             document.at_css("#title")
      clean_text(text(node))
    end

    def extract_price(document)
      offscreen = document.css(".a-price .a-offscreen").map { |n| text(n) }.compact.reject(&:empty?).first
      return clean_text(offscreen) if offscreen

      whole = document.at_css("span.a-price-whole")
      fraction = document.at_css("span.a-price-fraction")
      if whole
        sym_node = document.at_css("span.a-price-symbol")
        sym = sym_node ? text(sym_node) : "$"
        frac = text(fraction)
        parts = [ sym, text(whole), frac ? ".#{frac}" : nil ].compact.join
        return clean_text(parts)
      end

      deal = document.at_css("#corePrice_feature_div span.a-price") ||
             document.at_css("#sns-base-price") ||
             document.at_css("[data-a-color='price'] .a-offscreen")
      clean_text(text(deal))
    end

    def extract_rating(document)
      popover = document.at_css("#acrPopover")
      title_attr = popover&.[]("title")
      return parse_rating_from_string(title_attr) if title_attr

      icon_alt = document.css("i.a-icon-star, i.a-icon-star-medium, i.a-icon-star-small, .a-star-medium-review").flat_map { |i| i.css(".a-icon-alt") }.first
      parsed = parse_rating_from_string(text(icon_alt))
      return parsed if parsed

      nil
    end

    def parse_rating_from_string(str)
      return nil if str.blank?

      m = str.match(/#{RATING_NUM.source}\s*out\s*of\s*5(?:\s*stars?)?/i) ||
          str.match(/#{RATING_NUM.source}\s+stars?\b/i)
      m ? m[1].tr(",", ".").to_f : nil
    end

    def extract_review_count(document)
      node = document.at_css("#acrCustomerReviewText") ||
             document.at_css("span#acrCustomerReviewText") ||
             document.css("a#acrCustomerReviewLink").first
      raw = text(node)
      return nil if raw.blank?

      digits = raw.gsub(/[^\d]/, "")
      digits.present? ? digits.to_i : nil
    end

    def extract_availability(document)
      availability = document.at_css("#availability") ||
                     document.at_css("#availabilityInsideBuyBox_feature_div") ||
                     document.at_css("[data-cel-widget='availability_feature_div']")
      return nil unless availability

      # Prefer success / notice spans; skip hidden template nodes in nested divs
      span = availability.at_css(".a-color-success") ||
             availability.at_css(".a-color-price") ||
             availability.at_css("#deliveryMessageMirId") ||
             availability.css("span").find { |s| text(s).present? && text(s).length < 200 }
      clean_text(text(span))
    end

    def extract_images(document)
      urls = []

      landing = document.at_css("#landingImage") ||
                document.at_css("#imgBlkFront") ||
                document.at_css("#main-image")
      urls << landing["src"] if landing&.[]("src")&.start_with?("http")

      dynamic = landing&.[]("data-a-dynamic-image")
      if dynamic.present?
        begin
          h = JSON.parse(dynamic)
          urls.concat(h.keys) if h.is_a?(Hash)
        rescue JSON::ParserError
          # ignore
        end
      end

      document.css("#altImages ul li img, #imageBlock_feature_div img").each do |img|
        src = img["src"]
        urls << src if src&.include?("media-amazon.com") || src&.start_with?("http")
      end

      og = meta_content(document, "og:image")
      urls << og if og.present?

      urls.compact.uniq.first(20)
    end

    def extract_features(document)
      bullets = document.at_css("#feature-bullets") ||
                document.at_css("#productFactsDesktopExpander") ||
                document.at_css(".a-unordered-list.a-nostyle")
      return [] unless bullets

      items = []
      bullets.css("ul li span.a-list-item").each do |span|
        t = clean_text(text(span))
        items << t if t.present? && !t.match?(/^See more/i)
      end
      items.uniq
    end

    def extract_brand(document)
      row = document.at_css("tr.po-brand td.po-break-word") ||
            document.at_css("#bylineInfo")
      clean_text(text(row))
    end

    def meta_content(document, property)
      node = document.at_css("meta[property='#{property}']") ||
             document.at_css("meta[name='#{property}']")
      node&.[]("content")&.strip&.presence
    end
  end
end
