# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Boxcars::Embeddings::Hnswlib::BuildVectorStore do
  subject(:build_vector_store) { call_command }

  let(:arguments) do
    {
      training_data_path: training_data_path,
      index_file_path: index_file_path,
      split_chunk_size: 200,
      doc_text_file_path: doc_text_file_path
    }
  end
  let(:doc_text_file_path) { 'tmp/test_doc_text_file' }
  let(:training_data_path) { File.expand_path('spec/fixtures/training_data/**/*.md') }
  let(:index_file_path) { 'tmp/test_hnsw_index' }
  let(:openai_client) { instance_double(OpenAI::Client) }

  before do
    allow(ENV).to receive(:fetch).with('OPENAI_API_KEY', nil).and_return('mock_api_key')
    allow(OpenAI::Client).to receive(:new).and_return(openai_client)
    allow(openai_client).to receive(:is_a?).with(OpenAI::Client).and_return(true)

    allow(openai_client).to receive(:embeddings) do |_params|
      JSON.parse(File.read('spec/fixtures/embeddings/embeddings_response.json'))
    end
  end

  after do
    FileUtils.rm_rf(index_file_path)
    FileUtils.rm_rf(doc_text_file_path)
  end

  describe '#call' do
    # rubocop:disable RSpec/MultipleExpectations
    it 'builds the vector store successfully and creates the VectorStore' do
      expect(File.exist?(index_file_path)).to be false

      result = build_vector_store

      expect(File.exist?(index_file_path)).to be true
      expect(result[:vector_store]).to be_a(Hnswlib::HierarchicalNSW)
      # expect(result[:document_embeddings]).to be_a(Array)
      expect(result[:document_embeddings].first.keys).to eq(%i[doc_id embedding document])
    end
    # rubocop:enable RSpec/MultipleExpectations

    context 'when the training data path is invalid' do
      let(:training_data_path) { File.expand_path('invalid/path/**/*.md') }

      it 'raises an error' do
        expect { build_vector_store }.to raise_error(Boxcars::Error)
      end
    end

    context 'when there are no files in the training data path' do
      let(:training_data_path) { File.expand_path('spec/fixtures/training_data/empty/*.md') }

      it 'raises an error' do
        expect { build_vector_store }.to raise_error(Boxcars::Error)
      end
    end
  end

  context 'when the training_data path is invalid' do
    let(:training_data_path) { 'invalid/path/**/*.md' }

    it 'raises an error' do
      expect { build_vector_store }.to raise_error(Boxcars::Error)
    end
  end

  context 'when the index_file_path is invalid' do
    let(:index_file_path) { 'invalid/path/index.file' }

    it 'raises an error' do
      expect { build_vector_store }.to raise_error(Boxcars::Error)
    end
  end

  context 'when the split_chunk_size is invalid' do
    let(:arguments) do
      {
        training_data_path: training_data_path,
        index_file_path: index_file_path,
        split_chunk_size: 'invalid',
        doc_text_file_path: doc_text_file_path
      }
    end

    it 'raises an error' do
      expect { build_vector_store }.to raise_error(Boxcars::Error)
    end
  end

  def call_command
    described_class.call(**arguments)
  end
end
