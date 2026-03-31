# frozen_string_literal: true

require "nokogiri"

module Parsers
  class BaseParser
    def parse(_html)
      raise NotImplementedError, "#{self.class}#parse must be implemented"
    end

    def safe_parse(html)
      parse(html)
    rescue StandardError, NotImplementedError => e
      Rails.logger.warn("#{self.class}: Parsing failed: #{e.class} - #{e.message}")
      { error: true, error_message: "#{self.class} failed: #{e.message}" }
    end

    private

    def doc(html)
      Nokogiri::HTML(html)
    end

    def text(node)
      return nil if node.nil?

      node.text.strip.presence
    end

    def clean_text(str)
      return nil if str.nil?

      str.gsub(/\s+/, " ").strip.presence
    end
  end
end
