# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

# Service object to communicate with the Mask Service (Python FastAPI sidecar)
# Handles HTTP requests to the mask-service container for TLS fingerprint spoofing
class MaskServiceClient
  class Error < StandardError; end
  class TimeoutError < Error; end
  class NetworkError < Error; end
  class InvalidResponseError < Error; end

  DEFAULT_TIMEOUT = 30 # seconds
  # Default to localhost for local development, Docker will override via env var
  MASK_SERVICE_URL = ENV.fetch("MASK_SERVICE_URL", "http://localhost:8000")

  def initialize(timeout: DEFAULT_TIMEOUT)
    @timeout = timeout
  end

  # Fetches a URL using the mask service with Chrome TLS fingerprint spoofing
  #
  # @param url [String] The URL to fetch
  # @param proxy [String, nil] Optional proxy URL (e.g., "http://proxy:8080")
  # @return [Hash] Response containing :status, :html, :headers, :error, :error_message
  # @raise [TimeoutError] If the request times out
  # @raise [NetworkError] If there's a network error connecting to mask-service
  # @raise [InvalidResponseError] If the response is not valid JSON or missing required fields
  def fetch(url:, proxy: nil)
    uri = URI("#{MASK_SERVICE_URL}/v1/request")
    payload = { url: url }
    payload[:proxy] = proxy if proxy

    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = @timeout
    http.read_timeout = @timeout

    request = Net::HTTP::Post.new(uri.path)
    request["Content-Type"] = "application/json"
    request.body = payload.to_json

    response = http.request(request)

    parse_response(response)
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    raise TimeoutError, "Request to mask-service timed out after #{@timeout}s: #{e.message}"
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
    raise NetworkError, "Failed to connect to mask-service at #{MASK_SERVICE_URL}: #{e.message}"
  rescue JSON::ParserError => e
    raise InvalidResponseError, "Invalid JSON response from mask-service: #{e.message}"
  rescue StandardError => e
    raise Error, "Unexpected error calling mask-service: #{e.class} - #{e.message}"
  end

  private

  def parse_response(response)
    body = JSON.parse(response.body)

    {
      status: body["status"] || response.code.to_i,
      html: body["html"] || "",
      headers: body["headers"] || {},
      error: body["error"] || false,
      error_message: body["error_message"]
    }
  rescue JSON::ParserError => e
    raise InvalidResponseError, "Failed to parse response body: #{e.message}. Status: #{response.code}, Body: #{response.body[0..200]}"
  end
end
