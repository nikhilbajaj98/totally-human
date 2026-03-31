# frozen_string_literal: true

FactoryBot.define do
  factory :scrape_job do
    url { "https://example.com" }
    status { ScrapeJob::STATUS_PENDING }

    trait :done do
      status { ScrapeJob::STATUS_DONE }
      response_body do
        {
          status: 200,
          html: "<html><body>Hello</body></html>",
          headers: { "content-type" => "text/html" },
          error: false,
          error_message: nil,
          strategy: "free"
        }
      end
      parsed_data { { raw_html: "<html><body>Hello</body></html>" } }
      parser_used { "RawParser" }
      domain { "example.com" }
    end

    trait :failed do
      status { ScrapeJob::STATUS_FAILED }
      response_body do
        { error: true, error_message: "Connection refused" }
      end
    end
  end
end
