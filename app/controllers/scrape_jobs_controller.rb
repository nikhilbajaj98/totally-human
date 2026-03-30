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
  def show
    job = ScrapeJob.find(params[:id])

    render json: {
      id: job.id.to_s,
      url: job.url,
      status: job.status,
      response_body: job.response_body,
      created_at: job.created_at,
      updated_at: job.updated_at
    }
  rescue Mongoid::Errors::DocumentNotFound
    render json: { error: "Job not found" }, status: :not_found
  end

  # List all jobs
  # GET /scrape_jobs
  def index
    jobs = ScrapeJob.all.order(created_at: :desc).limit(100)

    render json: jobs.map { |job|
      {
        id: job.id.to_s,
        url: job.url,
        status: job.status,
        created_at: job.created_at,
        updated_at: job.updated_at
      }
    }
  end
end
