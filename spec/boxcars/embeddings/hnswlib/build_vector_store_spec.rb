# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/MultipleMemoizedHelpers
# rubocop:disable RSpec/MultipleExpectations
RSpec.describe Boxcars::Embeddings::Hnswlib::BuildVectorStore do
  subject(:build_vector_store) { call_command }

  let(:arguments) do
    {
      training_data_path: training_data_path,
      index_file_path: index_file_path,
      split_chunk_size: 200,
      json_doc_file_path: json_doc_file_path
    }
  end

  let(:training_data_path) { File.expand_path('spec/fixtures/training_data/**/*.md') }

  let(:json_doc_file_path) { File.join(Dir.tmpdir, 'test_doc_text_file.json') }
  let(:index_file_path) { File.join(Dir.tmpdir, 'test_hnsw_index.bin') }
  let(:hnswlib_config_json) { File.join(Dir.tmpdir, 'hnswlib_config.json') }

  let(:openai_client) { instance_double(OpenAI::Client) }
  let(:hnswlib_config) do
    {
      metric: 'l2',
      max_item: 10000,
      dim: 7,
      ef_construction: 200,
      max_outgoing_connection: 16
    }.to_json
  end

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
    FileUtils.rm_rf(json_doc_file_path) if json_doc_file_path
    FileUtils.rm_f(hnswlib_config_json)
  end

  describe '#call' do
    it 'builds the vector store successfully and creates the VectorStore' do
      expect(File.exist?(index_file_path)).to be false

      result = build_vector_store

      expect(File.exist?(index_file_path)).to be true
      expect(result[:vector_store]).to be_a(Hnswlib::HierarchicalNSW)
      expect(result[:document_embeddings].first.keys).to eq(%i[doc_id embedding document])
    end

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

    context 'when the json_doc_file_path is empty' do
      let(:json_doc_file_path) { nil }

      it 'still builds the vector store' do
        expect(File.exist?(index_file_path)).to be false

        result = build_vector_store

        expect(File.exist?(index_file_path)).to be true
        expect(result[:vector_store]).to be_a(Hnswlib::HierarchicalNSW)
        expect(result[:document_embeddings].first.keys).to eq(%i[doc_id embedding document])
      end
    end

    context 'with force_rebuild: true' do
      let(:arguments) do
        {
          training_data_path: training_data_path,
          index_file_path: index_file_path,
          split_chunk_size: 200,
          json_doc_file_path: json_doc_file_path,
          force_rebuild: true
        }
      end

      before do
        allow(Boxcars::Embeddings::Hnswlib::SaveToHnswlib).to receive(:call).and_call_original
      end

      it 'builds the vector store successfully and creates the VectorStore' do
        expect(File.exist?(index_file_path)).to be false

        result = build_vector_store

        expect(Boxcars::Embeddings::Hnswlib::SaveToHnswlib).to have_received(:call).once
        expect(result[:vector_store]).to be_a(Hnswlib::HierarchicalNSW)
        expect(result[:document_embeddings].first.keys).to eq(%i[doc_id embedding document])
      end
    end

    context 'with force_rebuild: false' do
      before do
        build_vector_store
      end

      let(:arguments) do
        {
          training_data_path: training_data_path,
          index_file_path: index_file_path,
          split_chunk_size: 200,
          json_doc_file_path: json_doc_file_path,
          force_rebuild: false
        }
      end

      it 'returns the vector store successfully and creates the VectorStore' do
        result = build_vector_store

        expect(File.exist?(index_file_path)).to be true
        expect(result[:vector_store]).to be_a(Hnswlib::HierarchicalNSW)
        expect(result[:document_embeddings].first.keys).to eq(%i[doc_id embedding document])
      end
    end
  end

  context 'when the training_data path is invalid' do
    let(:training_data_path) { 'invalid/path/**/*.md' }

    it 'raises an error' do
      expect { build_vector_store }.to raise_error(Boxcars::Error)
    end
  end

  context 'when the parent directory of index_file_path does not exist' do
    let(:index_file_path) { 'invalid_parent_directory/index.file' }

    before do
      FileUtils.rm_rf('invalid_parent_directory') if File.directory?('invalid_parent_directory')
    end

    after do
      FileUtils.rm_rf('invalid_parent_directory') if File.directory?('invalid_parent_directory')
    end

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
        json_doc_file_path: json_doc_file_path
      }
    end

    it 'raises an error' do
      expect { build_vector_store }.to raise_error(Boxcars::Error)
    end
  end
  # rubocop:enable RSpec/MultipleExpectations
  # rubocop:enable RSpec/MultipleMemoizedHelpers

  def call_command
    described_class.call(**arguments)
  end
end
