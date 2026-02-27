# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe "Notebook examples" do
  NOTEBOOKS = [
    "notebooks/boxcars_examples.ipynb",
    "notebooks/vector_search_examples.ipynb",
    "notebooks/embeddings/embeddings_example.ipynb",
    "notebooks/swagger_examples.ipynb"
  ].freeze

  VECTOR_NOTEBOOKS = [
    "notebooks/vector_search_examples.ipynb",
    "notebooks/embeddings/embeddings_example.ipynb"
  ].freeze

  MIGRATION_HEADER = "### OpenAI Backend (Migration)"
  MIGRATION_HINTS = [
    "# Optional migration pinning (uncomment if needed)",
    "# Boxcars.configuration.openai_official_require_native = true  # require native official SDK wiring"
  ].freeze

  def notebook_sources(path)
    parsed = JSON.parse(File.read(path))
    cells = parsed.fetch("cells")
    cells.map do |cell|
      source = cell["source"]
      source.is_a?(Array) ? source.join : source.to_s
    end
  end

  NOTEBOOKS.each do |path|
    it "#{path} has migration setup guidance at the top level" do
      sources = notebook_sources(path)

      expect(sources.any? { |src| src.include?(MIGRATION_HEADER) }).to be(true)
      migration_config_source = sources.find { |src| src.include?(MIGRATION_HINTS.first) }
      expect(migration_config_source).not_to be_nil

      MIGRATION_HINTS.each do |hint|
        expect(migration_config_source).to include(hint)
      end
    end
  end

  VECTOR_NOTEBOOKS.each do |path|
    it "#{path} uses the OpenAI client builder for vector flows" do
      sources = notebook_sources(path)
      expect(sources.any? { |src| src.include?("Boxcars::OpenAIClient.build") }).to be(true)
    end
  end
end
