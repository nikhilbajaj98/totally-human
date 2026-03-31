# frozen_string_literal: true

# Mongoid model representing a web scraping job
# Tracks the URL to scrape, job status, and the response from the mask service
class ScrapeJob
  include Mongoid::Document
  include Mongoid::Timestamps

  # Job status values
  STATUS_PENDING = "pending"
  STATUS_DONE = "done"
  STATUS_FAILED = "failed"
  STATUS_DEAD = "dead"

  MAX_RETRIES = 5

  field :url, type: String
  field :status, type: String, default: STATUS_PENDING
  field :response_body, type: Hash, default: {}
  field :parsed_data, type: Hash, default: {}
  field :parser_used, type: String
  field :domain, type: String
  field :failure_count, type: Integer, default: 0
  field :last_error, type: String

  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
  validates :status, inclusion: { in: [ STATUS_PENDING, STATUS_DONE, STATUS_FAILED, STATUS_DEAD ] }

  scope :pending, -> { where(status: STATUS_PENDING) }
  scope :done, -> { where(status: STATUS_DONE) }
  scope :failed, -> { where(status: STATUS_FAILED) }
  scope :dead, -> { where(status: STATUS_DEAD) }
  scope :by_status, ->(status) { where(status: status) if status.present? }

  def mark_done!(response_body, parsed_data: {}, parser_used: nil)
    update!(
      status: STATUS_DONE,
      response_body: response_body,
      parsed_data: parsed_data,
      parser_used: parser_used,
      domain: extract_domain
    )
  end

  def mark_failed!(error_message = nil)
    self.failure_count = (failure_count || 0) + 1
    safe_body = ScrapePayload.utf8({ error: true, error_message: error_message })
    safe_err = safe_body[:error_message]
    update!(
      status: STATUS_FAILED,
      response_body: safe_body,
      failure_count: self.failure_count,
      last_error: safe_err,
      parsed_data: {},
      parser_used: nil
    )
  end

  # Called by the Sidekiq death handler when all retries are exhausted
  def mark_dead!(error_message = nil)
    update!(
      status: STATUS_DEAD,
      last_error: error_message || last_error
    )
  end

  private

  def extract_domain
    URI.parse(url).host
  rescue URI::InvalidURIError
    nil
  end
end
