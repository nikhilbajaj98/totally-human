# frozen_string_literal: true

# Normalizes scrape response hashes for MongoDB and JSON APIs (UTF-8, scrub invalid bytes).
class ScrapePayload
  def self.utf8(obj)
    case obj
    when String
      utf8_string(obj)
    when Array
      obj.map { |e| utf8(e) }
    when Hash
      obj.transform_values { |v| utf8(v) }
    else
      obj
    end
  end

  def self.utf8_string(str)
    s = str.dup
    s.force_encoding(Encoding::UTF_8)
    return s if s.valid_encoding?

    s.force_encoding(Encoding::BINARY).encode(
      Encoding::UTF_8,
      invalid: :replace,
      undef: :replace,
      replace: "?"
    )
  end
end
