# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Pgvector optional dependency wiring" do
  let(:missing_pg_error) { Boxcars::ConfigurationError.new("Missing optional dependency 'pg'.") }

  before do
    allow(Boxcars::OptionalDependency).to receive(:require!)
      .with("pg", feature: "Boxcars::VectorStore::Pgvector")
      .and_raise(missing_pg_error)
  end

  it "raises setup guidance in BuildFromArray when pg is missing" do
    expect do
      Boxcars::VectorStore::Pgvector::BuildFromArray.new({})
    end.to raise_error(Boxcars::ConfigurationError, /optional dependency 'pg'/)
  end

  it "raises setup guidance in BuildFromFiles when pg is missing" do
    expect do
      Boxcars::VectorStore::Pgvector::BuildFromFiles.new(training_data_path: "spec/fixtures/training_data/**/*.md")
    end.to raise_error(Boxcars::ConfigurationError, /optional dependency 'pg'/)
  end

  it "raises setup guidance in SaveToDatabase when pg is missing" do
    expect do
      Boxcars::VectorStore::Pgvector::SaveToDatabase.new({})
    end.to raise_error(Boxcars::ConfigurationError, /optional dependency 'pg'/)
  end

  it "raises setup guidance in Search when pg is missing" do
    expect do
      Boxcars::VectorStore::Pgvector::Search.new({})
    end.to raise_error(Boxcars::ConfigurationError, /optional dependency 'pg'/)
  end
end
