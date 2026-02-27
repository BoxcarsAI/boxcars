# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

namespace :spec do
  NOTEBOOK_SMOKE_SPECS = %w[
    spec/notebooks/notebook_examples_spec.rb
  ].freeze

  VCR_OPENAI_REFRESH_SPECS = %w[
    spec/boxcars/calculator_spec.rb
    spec/boxcars/vector_answer_spec.rb
    spec/boxcars/vector_store/in_memory/build_from_array_spec.rb
    spec/boxcars/vector_store/pgvector/build_from_array_spec.rb
  ].freeze

  MODERNIZATION_RUNTIME_SPECS = %w[
    spec/boxcars/engines_spec.rb
    spec/boxcars/engine/capabilities_spec.rb
    spec/boxcars/boxcar_tool_spec.rb
    spec/boxcars/tool_calling_train_spec.rb
    spec/boxcars/json_engine_boxcar_schema_spec.rb
    spec/boxcars/mcp_helpers_spec.rb
    spec/boxcars/mcp_stdio_client_spec.rb
    spec/boxcars/mcp_tool_boxcar_spec.rb
  ].freeze

  OPENAI_CLIENT_PARITY_SPECS = %w[
    spec/boxcars/configuration_spec.rb
    spec/boxcars/openai_compatible_client_spec.rb
    spec/boxcars/openai_official_client_path_spec.rb
    spec/boxcars/openai_spec.rb
    spec/boxcars/openai_compatible_provider_client_wiring_spec.rb
    spec/boxcars/groq_spec.rb
    spec/boxcars/gemini_ai_spec.rb
    spec/boxcars/ollama_spec.rb
  ].freeze

  OPENAI_CLIENT_OFFICIAL_ONLY_SPECS = %w[
    spec/boxcars/configuration_spec.rb
    spec/boxcars/openai_compatible_client_spec.rb
    spec/boxcars/openai_official_client_path_spec.rb
    spec/boxcars/openai_compatible_provider_client_wiring_spec.rb
  ].freeze

  desc "Run notebook smoke specs (structure + migration setup compatibility)"
  task :notebooks_smoke do
    sh "bundle exec rspec #{NOTEBOOK_SMOKE_SPECS.join(' ')}"
  end

  desc "Run live notebook compatibility checks (requires OPENAI_ACCESS_TOKEN)"
  task :notebooks_live do
    sh "bundle exec ruby script/notebooks_live_check.rb"
  end

  desc "Run targeted OpenAI/embedding VCR cassette suite (no re-record)"
  task :vcr_openai_smoke do
    sh "bundle exec rspec #{VCR_OPENAI_REFRESH_SPECS.join(' ')}"
  end

  desc "Re-record targeted OpenAI/embedding VCR cassette suite (requires network + OPENAI_ACCESS_TOKEN)"
  task :vcr_openai_refresh do
    token = ENV.fetch("OPENAI_ACCESS_TOKEN", "").to_s.strip
    if token.empty? && File.exist?(".env")
      begin
        require "dotenv"
        token = Dotenv.parse(".env").fetch("OPENAI_ACCESS_TOKEN", "").to_s.strip
      rescue LoadError
        # no-op; fall back to current token value
      end
    end

    if token.empty?
      raise "OPENAI_ACCESS_TOKEN is required for spec:vcr_openai_refresh (env var or .env)"
    end

    sh "NO_VCR=true bundle exec rspec #{VCR_OPENAI_REFRESH_SPECS.join(' ')}"
  end

  desc "Run OpenAI client parity specs (official client contract path)"
  task :openai_client_parity do
    sh "bundle exec rspec #{OPENAI_CLIENT_PARITY_SPECS.join(' ')}"
  end

  desc "Run OpenAI client parity specs (official-safe subset)"
  task :openai_client_parity_official do
    sh "bundle exec rspec #{OPENAI_CLIENT_OFFICIAL_ONLY_SPECS.join(' ')}"
  end

  desc "Run modernization regression suite (aliases/tool-calling/MCP/JSON schema + OpenAI client parity lanes)"
  task :modernization do
    sh "bundle exec rspec #{NOTEBOOK_SMOKE_SPECS.join(' ')}"
    sh "bundle exec rspec #{MODERNIZATION_RUNTIME_SPECS.join(' ')}"
    sh "bundle exec rspec #{OPENAI_CLIENT_PARITY_SPECS.join(' ')}"
    sh "bundle exec rspec #{OPENAI_CLIENT_OFFICIAL_ONLY_SPECS.join(' ')}"
  end

  desc "Run minimal-dependency bundle check (core load + optional gem setup errors)"
  task :minimal_dependencies do
    minimal_gemfile = File.expand_path("script/minimal/Gemfile", __dir__)
    check_script = File.expand_path("script/minimal_dependencies_check.rb", __dir__)

    Bundler.with_unbundled_env do
      sh %(BUNDLE_GEMFILE="#{minimal_gemfile}" bundle install)
      sh %(BUNDLE_GEMFILE="#{minimal_gemfile}" bundle exec ruby "#{check_script}")
    end
  end
end

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: %i[spec rubocop]

begin
  require "github_changelog_generator/task"

  GitHubChangelogGenerator::RakeTask.new :changelog do |config|
    config.user = "BoxcarsAI"
    config.project = "boxcars"
  end
rescue LoadError
  desc "Generate changelog (install github_changelog_generator gem first)"
  task :changelog do
    warn(
      "github_changelog_generator is not installed. " \
      "Run `bundle add github_changelog_generator --group development,test --skip-install` " \
      "to enable this task."
    )
  end
end
