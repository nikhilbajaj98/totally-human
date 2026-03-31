# frozen_string_literal: true

module Parsers
  # Parses Amazon search results pages (/s?…, /s/ref=…) into structured product cards.
  # DOM varies by locale, A/B layout, and desktop vs mobile; multiple selectors are tried.
  class AmazonSearchParser < BaseParser
    CAPTCHA_PATTERNS = [
      /sorry! we just need to make sure you're not a robot/i,
      %r{api/services/validation}, # robot check flow
      /enter the characters you see below/i,
      %r{type="hidden"[^>]+name="amzn-r"},
      /cvf-page-content/i
    ].freeze

    SPONSORED_MARKERS = [
      /sponsored/i,
      /adfeedback/i,
      /sp-sponsored/i
    ].freeze

    def parse(html)
      return search_error_result(:robot_check) if robot_page?(html)

      document = doc(html)

      {
        products: extract_products(document),
        search_metadata: extract_search_metadata(document)
      }
    end

    private

    def robot_page?(raw)
      s = raw.to_s
      CAPTCHA_PATTERNS.any? { |p| s.match?(p) }
    end

    def search_error_result(reason)
      {
        robot_check: true,
        reason: reason,
        products: [],
        search_metadata: {}
      }
    end

    def extract_products(document)
      cards = document.css(
        'div[data-component-type="s-search-result"],' \
        'div[data-component-type="sp-sponsored-result"],' \
        'div[data-component-type="s-sponsored-result"]'
      )
      cards = document.css("div.s-result-item[data-asin]") if cards.empty?

      seen = {}
      products = []

      cards.each do |node|
        asin = node["data-asin"].to_s.strip
        next if asin.empty? || seen[asin]

        title_a = find_title_link(node)
        next unless title_a

        title = clean_text(text(title_a))
        next if title.nil? || title.empty?

        href = title_a["href"].to_s
        next if href.blank?

        seen[asin] = true
        products << {
          position: products.size + 1,
          asin: asin,
          title: title,
          url: absolutize_amazon_url(href),
          price: extract_card_price(node),
          rating: extract_card_rating(node),
          review_count: extract_card_review_count(node),
          image_url: extract_card_image(node),
          is_sponsored: sponsored?(node)
        }
      end

      products
    end

    def find_title_link(node)
      node.at_css('h2 a[href*="/dp/"]') ||
        node.at_css('h2 a[href*="/gp/product/"]') ||
        node.at_css(".a-size-medium.a-color-base.a-text-normal")&.at_css("a[href]") ||
        node.at_css("h2 a.a-link-normal") ||
        node.at_css("a.a-link-normal.s-underline-text") ||
        node.at_css("h2 a[href]")
    end

    def extract_card_price(node)
      off = node.at_css(".a-price .a-offscreen")
      return clean_text(text(off)) if off

      whole = node.at_css(".a-price-whole")
      frac = node.at_css(".a-price-fraction")
      if whole
        sym = node.at_css(".a-price-symbol")
        s = sym ? text(sym) : ""
        f = frac ? ".#{text(frac)}" : ""
        clean_text("#{s}#{text(whole)}#{f}")
      end
    end

    def extract_card_rating(node)
      alt = node.at_css("i.a-icon-star-small .a-icon-alt, i.a-icon-star .a-icon-alt, .a-icon-alt")
      parse_stars(text(alt))
    end

    def parse_stars(str)
      return nil if str.blank?

      m = str.match(/(\d+[.,]\d+)\s*out of\s*5/i) || str.match(/(\d+)\s*out of\s*5\s*stars/i)
      m ? m[1].tr(",", ".").to_f : nil
    end

    def extract_card_review_count(node)
      link = node.at_css("a[href*='product-reviews']") ||
             node.at_css("span.a-size-base.s-underline-text")
      raw = text(link)
      return nil if raw.blank?

      digits = raw.gsub(/[^\d]/, "")
      digits.present? ? digits.to_i : nil
    end

    def extract_card_image(node)
      img = node.at_css("img.s-image") ||
            node.at_css(".s-image") ||
            node.at_css("img[data-image-latency]")
      src = img&.[]("src")
      return nil if src.blank? || src.start_with?("data:")

      src
    end

    def sponsored?(node)
      type = node["data-component-type"].to_s
      return true if type.include?("sponsored")

      raw = node.to_html
      SPONSORED_MARKERS.any? { |m| raw.match?(m) }
    end

    def extract_search_metadata(document)
      meta = {}
      stats = document.at_css(".s-breadcrumb, span[data-component-type='s-result-count']")
      t = clean_text(text(stats))
      meta[:result_header] = t if t.present?

      bar = document.at_css("#twotabsearchtextbox")&.[]("value") ||
            document.at_css("input[name='field-keywords']")&.[]("value")
      meta[:query] = bar if bar.present?

      total = document.at_css("[data-component-type='s-result-info-bar']")
      meta[:results_info] = clean_text(text(total)) if total

      meta.compact
    end

    def absolutize_amazon_url(href)
      return href if href.start_with?("http")
      return "https://www.amazon.com#{href}" if href.start_with?("/")

      href
    end
  end
end
