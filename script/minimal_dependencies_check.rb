# frozen_string_literal: true

require "boxcars"

module MinimalDependenciesCheck
  module_function

  def run
    puts "Loaded Boxcars #{Boxcars::VERSION}"

    assert_missing_optional("openai") do
      Boxcars::OpenAIClient.validate_client_configuration!
    end

    assert_missing_optional("faraday") do
      Boxcars::Perplexityai.new.client(
        prompt: Boxcars::Prompt.new(template: "ping"),
        inputs: {},
        perplexity_api_key: "test-key"
      )
    end

    assert_missing_optional("ruby-anthropic") do
      Boxcars::Anthropic.new.client(
        prompt: Boxcars::Prompt.new(template: "ping"),
        inputs: {},
        anthropic_api_key: "test-key"
      )
    end

    assert_missing_optional("google_search_results") do
      Boxcars::GoogleSearch.new(serpapi_api_key: "test-key")
    end

    assert_missing_optional("nokogiri") do
      Boxcars::XNode.from_xml("<root><value>1</value></root>")
    end

    assert_missing_optional("hnswlib") do
      Boxcars::VectorStore::Hnswlib::SaveToHnswlib.new([])
    end

    assert_missing_optional("activerecord") do
      Boxcars::ActiveRecord.new(models: [])
    end

    assert_missing_optional("activerecord") do
      Boxcars::SQLActiveRecord.new(connection: Object.new)
    end

    assert_missing_optional("sequel") do
      Boxcars::SQLSequel.new(connection: Object.new)
    end

    assert_missing_optional("pg") do
      Boxcars::VectorStore::Pgvector::BuildFromArray.new({})
    end

    puts "Minimal dependency check passed."
  end

  def assert_missing_optional(gem_name)
    yield
    raise "Expected missing optional gem '#{gem_name}', but no error was raised."
  rescue Boxcars::ConfigurationError => e
    unless e.message.include?("optional gem '#{gem_name}'")
      raise "Expected error to mention optional gem '#{gem_name}', got: #{e.message.inspect}"
    end

    puts "OK: #{gem_name}"
  rescue StandardError => e
    raise "Expected Boxcars::ConfigurationError for '#{gem_name}', got #{e.class}: #{e.message}"
  end
end

MinimalDependenciesCheck.run
