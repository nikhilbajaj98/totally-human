# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScrapeWorker do
  let(:strategy) { instance_double(ScraperStrategy) }

  let(:success_response) do
    { status: 200, html: "<html>OK</html>", headers: {}, error: false, error_message: nil, strategy: "free" }
  end

  before do
    allow(ScraperStrategy).to receive(:new).and_return(strategy)
  end

  describe "#perform" do
    it "marks the job as done on successful scrape" do
      job = create(:scrape_job, url: "https://example.com")
      allow(strategy).to receive(:execute).and_return(success_response)

      described_class.new.perform(job.id.to_s)

      job.reload
      expect(job.status).to eq("done")
      expect(job.response_body["strategy"]).to eq("free")
    end

    it "stores parsed_data and parser_used from the parser" do
      job = create(:scrape_job, url: "https://example.com")
      allow(strategy).to receive(:execute).and_return(success_response)

      described_class.new.perform(job.id.to_s)

      job.reload
      expect(job.parser_used).to eq("RawParser")
      expect(job.parsed_data).to have_key("raw_html")
      expect(job.domain).to eq("example.com")
    end

    it "uses GoogleSearchParser for Google search URLs" do
      job = create(:scrape_job, url: "https://www.google.com/search?q=test")
      allow(strategy).to receive(:execute).and_return(success_response)

      described_class.new.perform(job.id.to_s)

      job.reload
      expect(job.parser_used).to eq("GoogleSearchParser")
    end

    it "calls strategy.execute with the job URL" do
      job = create(:scrape_job, url: "https://test.com")
      allow(strategy).to receive(:execute).and_return(success_response)

      described_class.new.perform(job.id.to_s)

      expect(strategy).to have_received(:execute).with(url: "https://test.com")
    end

    it "marks the job as failed on strategy error and re-raises" do
      job = create(:scrape_job, url: "https://example.com")
      allow(strategy).to receive(:execute).and_raise(ScraperStrategy::Error, "Both failed")

      expect { described_class.new.perform(job.id.to_s) }
        .to raise_error(ScraperStrategy::Error)

      job.reload
      expect(job.status).to eq("failed")
      expect(job.response_body["error_message"]).to eq("Both failed")
    end

    it "marks the job as failed on budget exceeded and re-raises" do
      job = create(:scrape_job, url: "https://example.com")
      allow(strategy).to receive(:execute).and_raise(ScraperStrategy::BudgetExceededError, "Limit reached")

      expect { described_class.new.perform(job.id.to_s) }
        .to raise_error(ScraperStrategy::BudgetExceededError)

      job.reload
      expect(job.status).to eq("failed")
    end

    it "raises Mongoid::Errors::DocumentNotFound for missing job" do
      expect { described_class.new.perform("000000000000000000000000") }
        .to raise_error(Mongoid::Errors::DocumentNotFound)
    end
  end
end
