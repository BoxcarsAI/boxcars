# frozen_string_literal: true

require "boxcars"

require "bundler/setup"
require "dotenv/load"
require "ruby/openai"
require "vcr"
require "debug"
require "support/helpdesk_sample_app"

Dir[File.expand_path("spec/support/**/*.rb")].sort.each { |f| require f }
VCR.configure do |c|
  c.hook_into :webmock
  c.cassette_library_dir = "spec/fixtures/cassettes"
  c.default_cassette_options = { record: ENV["NO_VCR"] == "true" ? :all : :new_episodes,
                                 match_requests_on: [:method, :uri, VCRMultipartMatcher.new] }
  c.filter_sensitive_data("<SERPAPI_API_KEY>") { Boxcars.configuration.serpapi_api_key }
  c.filter_sensitive_data("<openai_access_token>") { Boxcars.configuration.openai_access_token }
  c.filter_sensitive_data("<OPENAI_ORGANIZATION_ID>") { Boxcars.configuration.organization_id }
  # c.filter_sensitive_data("<Authorization>") { ENV.fetch("MC_API_TOKEN", "") }
end

RSpec.configure do |c|
  # Enable flags like --only-failures and --next-failure
  c.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  c.disable_monkey_patching!

  c.expect_with :rspec do |rspec|
    rspec.syntax = :expect
  end

  c.before do |example|
    otoken = example.metadata[:skip_tokens] ? nil : ENV.fetch("OPENAI_ACCESS_TOKEN", "abcdef")
    stoken = example.metadata[:skip_tokens] ? nil : ENV.fetch("SERPAPI_API_KEY", "abcdefg")
    log_prompts = ENV.fetch("LOG_PROMPTS", false)
    log_generated = ENV.fetch("LOG_GEN", false)
    mc_token = ENV.fetch("MC_API_TOKEN", "ABC123def456")
    allow(ENV).to receive(:fetch).with("OPENAI_ACCESS_TOKEN", nil).and_return(otoken)
    allow(ENV).to receive(:fetch).with("SERPAPI_API_KEY", nil).and_return(stoken)
    allow(ENV).to receive(:fetch).with("LOG_PROMPTS", false).and_return(log_prompts)
    allow(ENV).to receive(:fetch).with("LOG_GEN", false).and_return(log_generated)
    allow(ENV).to receive(:fetch).with("MC_API_TOKEN", "").and_return(mc_token)
  end
end

RSPEC_ROOT = File.dirname __FILE__
