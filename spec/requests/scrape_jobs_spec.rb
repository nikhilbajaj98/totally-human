# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ScrapeJobs API", type: :request do
  before do
    allow(ScrapeWorker).to receive(:perform_async)
  end

  describe "POST /scrape_jobs" do
    it "creates a job and returns 201 with pending status" do
      post "/scrape_jobs", params: { url: "https://example.com" }

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("pending")
      expect(body["url"]).to eq("https://example.com")
      expect(body["id"]).to be_present
    end

    it "enqueues a ScrapeWorker" do
      post "/scrape_jobs", params: { url: "https://example.com" }

      expect(ScrapeWorker).to have_received(:perform_async).with(String)
    end

    it "returns 422 when URL is missing" do
      post "/scrape_jobs", params: {}

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["errors"]).to be_present
    end

    it "returns 422 for an invalid URL" do
      post "/scrape_jobs", params: { url: "not-a-url" }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /scrape_jobs/:id" do
    it "returns the job with full details" do
      job = create(:scrape_job, :done)

      get "/scrape_jobs/#{job.id}"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["id"]).to eq(job.id.to_s)
      expect(body["status"]).to eq("done")
      expect(body["response_body"]).to be_present
    end

    it "returns 404 for a non-existent job" do
      get "/scrape_jobs/000000000000000000000000"

      expect(response).to have_http_status(:not_found)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("Job not found")
    end
  end

  describe "GET /scrape_jobs" do
    it "returns a list of recent jobs" do
      create(:scrape_job, url: "https://a.com")
      create(:scrape_job, url: "https://b.com")

      get "/scrape_jobs"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.length).to eq(2)
      expect(body.map { |j| j["url"] }).to contain_exactly("https://a.com", "https://b.com")
    end

    it "returns an empty array when no jobs exist" do
      get "/scrape_jobs"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end
  end
end
