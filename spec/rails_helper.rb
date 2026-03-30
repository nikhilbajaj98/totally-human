# frozen_string_literal: true

require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"

abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"
require "webmock/rspec"
require "database_cleaner-mongoid"

WebMock.disable_net_connect!

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods

  config.before(:suite) do
    DatabaseCleaner[:mongoid].strategy = :deletion
    DatabaseCleaner[:mongoid].clean
  end

  config.around(:each) do |example|
    DatabaseCleaner[:mongoid].cleaning { example.run }
  end

  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end
