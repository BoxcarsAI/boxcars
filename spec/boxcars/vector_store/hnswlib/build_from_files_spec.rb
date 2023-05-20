# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Boxcars::VectorStore::Hnswlib::BuildFromFiles do
  subject(:build_vector_store) { call_command }

  let(:arguments) do
    {
      training_data_path: training_data_path,
      index_file_path: index_file_path,
      split_chunk_size: 900,
      json_doc_file_path: json_doc_file_path
    }
  end

  let(:training_data_path) { 'spec/fixtures/training_data/**/*.md' }
  let(:index_file_path) { File.join(Dir.tmpdir, 'test_hnsw_index.bin') }
  let(:json_doc_file_path) { File.join(Dir.tmpdir, 'test_doc_text_file.json') }
  let(:parsed_texts) { JSON.parse(File.read(json_doc_file_path), symbolize_names: true) }
  let(:openai_client) { instance_double(OpenAI::Client) }

  before do
    allow(OpenAI::Client).to receive(:new).and_return(openai_client)
    allow(openai_client).to receive(:is_a?).with(OpenAI::Client).and_return(true)
    allow(openai_client).to receive(:embeddings) do |_params|
      JSON.parse(File.read('spec/fixtures/embeddings/embeddings_response.json'))
    end
    allow(Boxcars::VectorStore::Hnswlib::SaveToHnswlib).to receive(:call).and_return(true)
  end

  after do
    FileUtils.rm_rf(index_file_path)
    FileUtils.rm_rf(json_doc_file_path) if json_doc_file_path
  end

  describe '#call' do
    it 'returns hnswlib type' do
      expect(build_vector_store[:type]).to eq(:hnswlib)
    end

    it 'returns vector_store' do
      expect(build_vector_store[:vector_store].size).to eq(19)
    end

    it 'returns Boxcars::VectorStore::Document' do
      expected = build_vector_store[:vector_store].map { |x| x.class.name }.uniq
      expect(expected).to eq(['Boxcars::VectorStore::Document'])
    end

    it 'returns document_embeddings' do
      build_vector_store[:vector_store].each do |doc|
        expect(doc.content.size).to be_positive
        expect(doc.embedding.size).to eq(7)
        expect(doc.metadata.keys).to eq(%i[doc_id dim metric max_item base_dir_path index_file_path json_doc_file_path])
      end
    end

    it 'calls Boxcars::VectorStore::Hnswlib::SaveToHnswlib' do
      build_vector_store

      expect(Boxcars::VectorStore::Hnswlib::SaveToHnswlib).to have_received(:call).once
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
        expect(build_vector_store[:vector_store].size).to eq(19)
      end
    end

    context 'with force_rebuild: true' do
      let(:arguments) do
        {
          training_data_path: training_data_path,
          index_file_path: index_file_path,
          split_chunk_size: 900,
          json_doc_file_path: json_doc_file_path,
          force_rebuild: true
        }
      end

      before do
        allow(Boxcars::VectorStore::Hnswlib::SaveToHnswlib).to receive(:call).and_return(true)
      end

      it 'calls Boxcars::VectorStore::Hnswlib::LoadFromDisk' do
        build_vector_store

        expect(Boxcars::VectorStore::Hnswlib::SaveToHnswlib).to have_received(:call).once
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
          split_chunk_size: 900,
          json_doc_file_path: json_doc_file_path,
          force_rebuild: false
        }
      end

      it 'returns the vector store successfully and creates the VectorStore' do
        expect(build_vector_store[:vector_store].size).to eq(19)
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

  def call_command
    described_class.call(arguments)
  end
end
