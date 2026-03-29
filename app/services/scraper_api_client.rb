# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

# Service object to communicate with a premium scraping API (e.g., ScrapingBee)
# Used as a fallback when the free mask-service fails
class ScraperApiClient
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class TimeoutError < Error; end
  class NetworkError < Error; end
  class InvalidResponseError < Error; end
  class BudgetExceededError < Error; end

  DEFAULT_TIMEOUT = 30 # seconds
  SCRAPER_API_URL = "https://app.scrapingbee.com/api/v1/"

  def initialize(timeout: DEFAULT_TIMEOUT)
    @timeout = timeout
  end

  # Fetches a URL using the ScrapingBee API.
  # API key: set SCRAPINGBEE_API_KEY in env, or rails credentials (scrapingbee_api_key).
  #
  # @param url [String] The URL to fetch
  # @return [Hash] Response containing :status, :html, :headers, :error, :error_message
  # @raise [ConfigurationError] If no API key is configured
  # @raise [TimeoutError] If the request times out
  # @raise [NetworkError] If there's a network error connecting to premium API
  # @raise [InvalidResponseError] If the response is not valid JSON or missing required fields
  def fetch(url:)
    api_key = api_key!
    uri = URI(SCRAPER_API_URL)
    uri.query = URI.encode_www_form({
      api_key: api_key,
      url: url
    })

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = @timeout
    http.read_timeout = @timeout

    request = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(request)

    parse_response(response)
  rescue Net::TimeoutError, Net::OpenTimeout => e
    raise TimeoutError, "Request to ScrapingBee API timed out after #{@timeout}s: #{e.message}"
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
    raise NetworkError, "Failed to connect to ScrapingBee API at #{SCRAPER_API_URL}: #{e.message}"
  rescue ConfigurationError => e
    raise Error, "ScrapingBee API configuration error: #{e.message}"
  rescue BudgetExceededError
    raise
  rescue StandardError => e
    raise Error, "Unexpected error calling ScrapingBee API: #{e.class} - #{e.message}"
  end

  private

  def api_key!
    key = ENV["SCRAPINGBEE_API_KEY"].presence || Rails.application.credentials.scrapingbee_api_key
    raise ConfigurationError, "ScrapingBee API key not configured. Set SCRAPINGBEE_API_KEY or rails credentials scrapingbee_api_key." unless key.present?
    key
  end

  def parse_response(response)
    status_code = response.code.to_i
    if status_code == 402
        raise BudgetExceededError, "ScrapingBee budget exceeded: #{response.body}"
    elsif status_code >= 400
      return {
        status: status_code,
        html: "",
        headers: response.to_hash,
        error: true,
        error_message: response.body
      }
    end

    {
      status: status_code,
      html: response.body,
      headers: response.to_hash,
      error: false,
      error_message: nil
    }
  end
end
