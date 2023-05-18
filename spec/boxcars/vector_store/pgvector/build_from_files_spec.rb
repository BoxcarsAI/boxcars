# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Boxcars::VectorStore::Pgvector::BuildFromFiles do
  subject(:result) { call_command }

  let(:arguments) do
    {
      training_data_path: training_data_path,
      split_chunk_size: 200,
      embedding_tool: embedding_tool,
      database_url: db_url,
      table_name: table_name,
      embedding_column_name: embedding_column_name,
      content_column_name: content_column_name,
      metadata_column_name: metadata_column_name
    }
  end

  let(:training_data_path) { File.expand_path('spec/fixtures/training_data/**/*.md') }
  let(:embedding_tool) { :openai }

  let(:db_url) { ENV['DATABASE_URL'] || 'postgres://postgres@localhost/boxcars_test' }
  let(:table_name) { 'items' }
  let(:embedding_column_name) { 'embedding' }
  let(:content_column_name) { 'content' }
  let(:metadata_column_name) { 'metadata' }
  let(:openai_client) { instance_double(OpenAI::Client) }
  let(:documents) do
    [
      Boxcars::VectorStore::Document.new(
        content: "hello", metadata: { a: 1, id: 1 }, embedding: [1.0, 2.0, 3.0]
      ),
      Boxcars::VectorStore::Document.new(
        content: "hi", metadata: { a: 1, id: 2 }, embedding: [4.0, 5.0, 6.0]
      ),
      Boxcars::VectorStore::Document.new(
        content: "bye", metadata: { a: 1, id: 3 }, embedding: [7.0, 8.0, 9.0]
      ),
      Boxcars::VectorStore::Document.new(
        content: "what's this", metadata: { a: 1, id: 4 }, embedding: [10.0, 11.0, 12.0]
      )
    ]
  end

  before do
    allow(OpenAI::Client).to receive(:new).and_return(openai_client)
    allow(openai_client).to receive(:is_a?).with(OpenAI::Client).and_return(true)
    allow(openai_client).to receive(:embeddings) do |_params|
      JSON.parse(File.read('spec/fixtures/embeddings/embeddings_response.json'))
    end
    allow(Boxcars::VectorStore::Pgvector::SaveToDatabase).to receive(:call).and_return(documents)
  end

  it 'returns pgvector type' do
    expect(result[:type]).to eq(:pgvector)
  end

  it 'returns Boxcars::VectorStore::Document' do
    expected = result[:vector_store].map { |x| x.class.name }.uniq
    expect(expected).to eq(['Boxcars::VectorStore::Document'])
  end

  it 'returns document_embeddings' do
    result[:vector_store].each do |doc|
      expect(doc.content.size).to be_positive
    end
  end

  it 'calls Boxcars::VectorStore::Pgvector::SaveToDatabase' do
    call_command

    expect(Boxcars::VectorStore::Pgvector::SaveToDatabase).to have_received(:call).once
  end

  context 'when Boxcars::VectorStore::Pgvector::SaveToDatabase returns an error' do
    before do
      allow(Boxcars::VectorStore::Pgvector::SaveToDatabase).to receive(:call).and_raise(Boxcars::ArgumentError.new('db error'))
    end

    it 'raises an error' do
      expect { call_command }.to raise_error(Boxcars::Error)
    end
  end

  context 'when the training data path is invalid' do
    let(:training_data_path) { File.expand_path('invalid/path/**/*.md') }

    it 'raises an error' do
      expect { call_command }.to raise_error(Boxcars::Error)
    end
  end

  context 'when there are no files in the training data path' do
    let(:training_data_path) { File.expand_path('spec/fixtures/training_data/empty/*.md') }

    it 'raises an error' do
      expect { call_command }.to raise_error(Boxcars::Error)
    end
  end

  context 'when the split_chunk_size is invalid' do
    let(:arguments) do
      {
        training_data_path: training_data_path,
        split_chunk_size: 'invalid',
        embedding_tool: embedding_tool
      }
    end

    it 'raises an error' do
      expect { call_command }.to raise_error(Boxcars::Error)
    end
  end

  def call_command
    described_class.call(arguments)
  end
end
