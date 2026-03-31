# frozen_string_literal: true

namespace :demo do
  desc "Submit diverse scrape jobs via HTTP, poll until complete, print colored summary (needs api+worker up)"
  task run: :environment do
    Demo::Runner.new.run
  end

  desc "Insert sample completed jobs into MongoDB (development only, or ALLOW_DEMO_SEED=true)"
  task seed: :environment do
    Demo::Seeder.run
  end

  desc "Enqueue many scrape jobs quickly to populate Prometheus/Grafana (set DEMO_LOAD_COUNT, DEMO_LOAD_SLEEP_MS, DEMO_API_URL)"
  task load: :environment do
    Demo::MetricsLoad.fire
  end
end
