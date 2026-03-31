# frozen_string_literal: true

# API controller for creating and querying scrape jobs
class ScrapeJobsController < ApplicationController
  # Create a new scrape job
  # POST /scrape_jobs
  # Body: { "url": "https://example.com" }
  def create
    job = ScrapeJob.new(url: params[:url])

    if job.save
      # Enqueue the job for processing
      ScrapeWorker.perform_async(job.id.to_s)

      render json: {
        id: job.id.to_s,
        url: job.url,
        status: job.status,
        created_at: job.created_at
      }, status: :created
    else
      render json: { errors: job.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # Get job status
  # GET /scrape_jobs/:id
  # Optional: ?format_type=parsed to return only structured data
  def show
    job = ScrapeJob.find(params[:id])

    if params[:format_type] == "parsed"
      render json: {
        id: job.id.to_s,
        url: job.url,
        status: job.status,
        parsed_data: job.parsed_data,
        parser_used: job.parser_used
      }
    else
      render json: {
        id: job.id.to_s,
        url: job.url,
        status: job.status,
        response_body: job.response_body,
        parsed_data: job.parsed_data,
        parser_used: job.parser_used,
        domain: job.domain,
        created_at: job.created_at,
        updated_at: job.updated_at
      }
    end
  rescue Mongoid::Errors::DocumentNotFound
    render json: { error: "Job not found" }, status: :not_found
  end

  # List jobs, optionally filtered by status
  # GET /scrape_jobs
  # GET /scrape_jobs?status=failed
  # GET /scrape_jobs?status=dead
  def index
    jobs = ScrapeJob.by_status(params[:status]).order(created_at: :desc).limit(100)

    render json: jobs.map { |job|
      payload = {
        id: job.id.to_s,
        url: job.url,
        status: job.status,
        created_at: job.created_at,
        updated_at: job.updated_at
      }

      if job.status.in?([ ScrapeJob::STATUS_FAILED, ScrapeJob::STATUS_DEAD ])
        payload[:failure_count] = job.failure_count
        payload[:last_error] = job.last_error
      end

      payload
    }
  end
end
