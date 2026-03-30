# frozen_string_literal: true

Yabeda.configure do
  group :totallyhuman do
    counter   :scrape_requests_total,
              tags: %i[strategy status],
              comment: "Total scrape requests by strategy (free/premium) and outcome (done/failed)"

    histogram :scrape_duration_seconds,
              tags: %i[strategy],
              buckets: [ 0.1, 0.5, 1, 2, 5, 10, 30, 60 ],
              comment: "Duration of scrape requests in seconds"

    counter   :fallbacks_total,
              tags: %i[reason],
              comment: "Total fallbacks from free to premium by trigger reason"

    gauge     :premium_budget_used,
              comment: "Current premium API usage count"

    counter   :cost_saved_total,
              comment: "Number of requests served by free path (each = one paid call saved)"
  end
end

Yabeda.configure!
