require "yabeda/prometheus"

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  mount Yabeda::Prometheus::Exporter => "/metrics"

  resources :scrape_jobs, only: [:create, :show, :index]
end
