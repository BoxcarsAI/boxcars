# frozen_string_literal: true

require "boxcars"

require "bundler/setup"
require "dotenv/load"
require "openai"
require "vcr"
require "debug"
require "support/helpdesk_sample_app"
require 'tmpdir'

Dir[File.expand_path("spec/support/**/*.rb")].each { |f| require f }
VCR.configure do |c|
  c.hook_into :webmock
  c.cassette_library_dir = "spec/fixtures/cassettes"
  c.default_cassette_options = { record: ENV["NO_VCR"] == "true" ? :all : :new_episodes,
                                 match_requests_on: [:method, :uri, VCRMultipartMatcher.new] }
  c.filter_sensitive_data("<SERPAPI_API_KEY>") { Boxcars.configuration.serpapi_api_key }
  c.filter_sensitive_data("<ANTHROPIC_API_KEY>") { Boxcars.configuration.anthropic_api_key }
  c.filter_sensitive_data("<GEMINI_API_KEY>") { Boxcars.configuration.gemini_api_key }
  c.filter_sensitive_data("<GROQ_API_KEY>") { Boxcars.configuration.groq_api_key }
  c.filter_sensitive_data("<CEREBRAS_API_KEY>") { Boxcars.configuration.groq_api_key }
  c.filter_sensitive_data("<COHERE_API_KEY>") { Boxcars.configuration.cohere_api_key }
  c.filter_sensitive_data("<ANTHROPIC_API_KEY>") { Boxcars.configuration.anthropic_api_key }
  c.filter_sensitive_data("<openai_access_token>") { Boxcars.configuration.openai_access_token }
  c.filter_sensitive_data("<OPENAI_ORGANIZATION_ID>") { Boxcars.configuration.organization_id }
  c.filter_sensitive_data("<TOGETHER_API_KEY>") { Boxcars.configuration.together_api_key }
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
    next if example.metadata[:live_env]

    otoken = example.metadata[:skip_tokens] ? nil : ENV.fetch("OPENAI_ACCESS_TOKEN", "abcdef")
    openai_api_key = example.metadata[:skip_tokens] ? nil : ENV.fetch("OPENAI_API_KEY", otoken)
    stoken = example.metadata[:skip_tokens] ? nil : ENV.fetch("SERPAPI_API_KEY", "abcdefg")
    atoken = example.metadata[:skip_tokens] ? nil : ENV.fetch("ANTHROPIC_API_KEY", "abcdefgh")
    ctoken = example.metadata[:skip_tokens] ? nil : ENV.fetch("COHERE_API_KEY", "abcdefgh")
    gtoken = example.metadata[:skip_tokens] ? nil : ENV.fetch("GROQ_API_KEY", "abcdefgh")
    htoken = example.metadata[:skip_tokens] ? nil : ENV.fetch("GEMINI_API_KEY", "abcdefgh")
    btoken = example.metadata[:skip_tokens] ? nil : ENV.fetch("CEREBRAS_API_KEY", "abcdefgh")
    ttoken = example.metadata[:skip_tokens] ? nil : ENV.fetch("TOGETHER_API_KEY", "abcdefgh")
    openai_official_require_native = ENV.fetch("OPENAI_OFFICIAL_REQUIRE_NATIVE", false)
    log_prompts = ENV.fetch("LOG_PROMPTS", false)
    log_generated = ENV.fetch("LOG_GEN", false)
    http_p = ENV.fetch('http_proxy', nil)
    allow(ENV).to receive(:fetch).with("OPENAI_ACCESS_TOKEN", nil).and_return(otoken)
    allow(ENV).to receive(:fetch).with("OPENAI_API_KEY", nil).and_return(openai_api_key)
    allow(ENV).to receive(:fetch).with("SERPAPI_API_KEY", nil).and_return(stoken)
    allow(ENV).to receive(:fetch).with("ANTHROPIC_API_KEY", nil).and_return(atoken)
    allow(ENV).to receive(:fetch).with("COHERE_API_KEY", nil).and_return(ctoken)
    allow(ENV).to receive(:fetch).with("GROQ_API_KEY", nil).and_return(gtoken)
    allow(ENV).to receive(:fetch).with("CEREBRAS_API_KEY", nil).and_return(btoken)
    allow(ENV).to receive(:fetch).with("TOGETHER_API_KEY", nil).and_return(ttoken)
    allow(ENV).to receive(:fetch).with("GEMINI_API_KEY", nil).and_return(htoken)
    allow(ENV).to receive(:fetch).with("OPENAI_OFFICIAL_REQUIRE_NATIVE", false).and_return(openai_official_require_native)
    allow(ENV).to receive(:fetch).with("LOG_PROMPTS", false).and_return(log_prompts)
    allow(ENV).to receive(:fetch).with("LOG_GEN", false).and_return(log_generated)
    allow(ENV).to receive(:fetch).with('http_proxy', nil).and_return(http_p)
    allow(ENV).to receive(:fetch).with('DEBUG_XML', false).and_return(false)
  end
end

RSPEC_ROOT = File.dirname __FILE__
