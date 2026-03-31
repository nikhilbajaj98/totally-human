# frozen_string_literal: true

module Demo
  # Inserts realistic completed ScrapeJob documents for API/Grafana browsing without workers.
  class Seeder
    SAMPLE_RESPONSE_FREE = {
      status: 200,
      html: "(demo seed — no live HTML)",
      headers: { "content-type" => "text/html" },
      error: false,
      error_message: nil,
      strategy: "free"
    }.freeze

    SAMPLE_RESPONSE_PREMIUM = SAMPLE_RESPONSE_FREE.merge(strategy: "premium").freeze

    SAMPLES = [
      {
        url: "https://news.ycombinator.com/",
        parser_used: "HackerNewsParser",
        domain: "news.ycombinator.com",
        parsed_data: {
          stories: [
            { position: 1, title: "Show HN: Demo seed story", url: "https://example.com/hn1",
              score: 100, author: "demo", comments_count: 42, hn_id: "1" }
          ],
          page_metadata: { has_more: true }
        },
        response_body: SAMPLE_RESPONSE_FREE
      },
      {
        url: "https://docs.python.org/3/tutorial/index.html",
        parser_used: "ArticleParser",
        domain: "docs.python.org",
        parsed_data: {
          title: "The Python Tutorial",
          author: nil,
          body_text: "Seeded demo excerpt: Python is an easy to learn language.",
          word_count: 12,
          language: "en"
        },
        response_body: SAMPLE_RESPONSE_FREE
      },
      {
        url: "https://www.amazon.com/s?k=demo+seed",
        parser_used: "AmazonSearchParser",
        domain: "www.amazon.com",
        parsed_data: {
          products: [
            { position: 1, asin: "B0DEMOSEED", title: "Demo USB hub", url: "https://www.amazon.com/dp/B0DEMOSEED",
              price: "$19.99", rating: 4.5, review_count: 500, image_url: "https://m.media-amazon.com/images/I/demo.jpg",
              is_sponsored: false }
          ],
          search_metadata: { result_header: "1-48 of over 1,000 results for \"demo seed\"" }
        },
        response_body: SAMPLE_RESPONSE_FREE
      },
      {
        url: "https://www.amazon.com/dp/B0DEMOPROD1",
        parser_used: "AmazonProductParser",
        domain: "www.amazon.com",
        parsed_data: {
          asin: "B0DEMOPROD1", title: "Demo countertop gadget",
          price: "$49.00", rating: 4.2, review_count: 99,
          availability: "In Stock", images: [], features: [ "Demo bullet A", "Demo bullet B" ], brand: "DemoBrand"
        },
        response_body: SAMPLE_RESPONSE_PREMIUM
      },
      {
        url: "https://www.google.com/search?q=demo+query",
        parser_used: "GoogleSearchParser",
        domain: "www.google.com",
        parsed_data: {
          organic_results: [
            { position: 1, title: "Demo search hit", link: "https://example.com/r1", snippet: "Seeded snippet." }
          ],
          related_searches: %w[demo related],
          search_metadata: { query: "demo query" }
        },
        response_body: SAMPLE_RESPONSE_FREE
      }
    ].freeze

    def self.run
      unless Rails.env.development? || ENV["ALLOW_DEMO_SEED"] == "true"
        warn "demo:seed skipped: only run in development, or set ALLOW_DEMO_SEED=true"
        return
      end

      removed = ScrapeJob.where(demo_seed: true).delete_all
      puts "Removed #{removed} previous demo_seed job(s)."

      SAMPLES.each do |attrs|
        ScrapeJob.create!(
          attrs.merge(
            status: ScrapeJob::STATUS_DONE,
            demo_seed: true,
            failure_count: 0,
            last_error: nil
          )
        )
      end

      puts "Seeded #{SAMPLES.size} completed ScrapeJob documents (demo_seed: true)."
      puts "Try: curl -s http://localhost:3000/scrape_jobs | jq"
    end
  end
end
