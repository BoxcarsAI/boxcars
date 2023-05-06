# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Boxcars::VectorStore::InMemory::BuildFromFiles do
  subject(:result) { call_command }

  let(:arguments) do
    {
      training_data_path: training_data_path,
      split_chunk_size: 200,
      embedding_tool: embedding_tool
    }
  end

  let(:training_data_path) { File.expand_path('spec/fixtures/training_data/**/*.md') }
  let(:embedding_tool) { :openai }
  let(:openai_client) { instance_double(OpenAI::Client) }

  before do
    allow(OpenAI::Client).to receive(:new).and_return(openai_client)
    allow(openai_client).to receive(:is_a?).with(OpenAI::Client).and_return(true)
    allow(openai_client).to receive(:embeddings) do |_params|
      JSON.parse(File.read('spec/fixtures/embeddings/embeddings_response.json'))
    end
    allow(Boxcars::VectorStore::Hnswlib::SaveToHnswlib).to receive(:call).and_return(true)
  end

  it 'returns in_memory type' do
    expect(result[:type]).to eq(:in_memory)
  end

  it 'returns same number of data as document size' do
    expect(result[:vector_store].size).to eq(15)
  end

  it 'returns Boxcars::VectorStore::Document' do
    expected = result[:vector_store].map { |x| x.class.name }.uniq
    expect(expected).to eq(['Boxcars::VectorStore::Document'])
  end

  it 'returns document_embeddings' do
    result[:vector_store].each do |doc|
      expect(doc.content.size).to be_positive
      expect(doc.embedding.size).to eq(7)
      expect(doc.metadata.keys).to eq(%i[doc_id training_data_path])
    end
  end

  context 'when the training data path is invalid' do
    let(:training_data_path) { File.expand_path('invalid/path/**/*.md') }

    it 'raises an error' do
      expect { result }.to raise_error(Boxcars::Error)
    end
  end

  context 'when there are no files in the training data path' do
    let(:training_data_path) { File.expand_path('spec/fixtures/training_data/empty/*.md') }

    it 'raises an error' do
      expect { result }.to raise_error(Boxcars::Error)
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
      expect { result }.to raise_error(Boxcars::Error)
    end
  end

  def call_command
    described_class.call(arguments)
  end
end
