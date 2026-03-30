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

  field :url, type: String
  field :status, type: String, default: STATUS_PENDING
  field :response_body, type: Hash, default: {}

  # Validations
  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
  validates :status, inclusion: { in: [ STATUS_PENDING, STATUS_DONE, STATUS_FAILED ] }

  # Scopes
  scope :pending, -> { where(status: STATUS_PENDING) }
  scope :done, -> { where(status: STATUS_DONE) }
  scope :failed, -> { where(status: STATUS_FAILED) }

  # Mark job as completed with response data
  def mark_done!(response_body)
    update!(status: STATUS_DONE, response_body: response_body)
  end

  # Mark job as failed with optional error message
  def mark_failed!(error_message = nil)
    update!(
      status: STATUS_FAILED,
      response_body: { error: true, error_message: error_message }
    )
  end
end
