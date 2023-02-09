# frozen_string_literal: true

require "boxcars"

require "bundler/setup"
require "dotenv/load"
require "ruby/openai"
require "vcr"
require "debug"

Dir[File.expand_path("spec/support/**/*.rb")].sort.each { |f| require f }

VCR.configure do |c|
  c.hook_into :webmock
  c.cassette_library_dir = "spec/fixtures/cassettes"
  c.default_cassette_options = { record: ENV["NO_VCR"] == "true" ? :all : :new_episodes,
                                 match_requests_on: [:method, :uri, VCRMultipartMatcher.new] }
  c.filter_sensitive_data("<SERPAPI_API_KEY>") { Boxcars.configuration.serpapi_api_key }
  c.filter_sensitive_data("<openai_access_token>") { Boxcars.configuration.openai_access_token }
  c.filter_sensitive_data("<OPENAI_ORGANIZATION_ID>") { Boxcars.configuration.organization_id }
end

RSpec.configure do |c|
  # Enable flags like --only-failures and --next-failure
  c.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  c.disable_monkey_patching!

  c.expect_with :rspec do |rspec|
    rspec.syntax = :expect
  end
end

RSPEC_ROOT = File.dirname __FILE__

# RSpec.configure do |config|
#   # Enable flags like --only-failures and --next-failure
#   config.example_status_persistence_file_path = ".rspec_status"

#   # Disable RSpec exposing methods globally on `Module` and `main`
#   config.disable_monkey_patching!

#   config.expect_with :rspec do |c|
#     c.syntax = :expect
#   end
# end
