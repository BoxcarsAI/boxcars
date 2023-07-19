# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Boxcars::VectorStore::Hnswlib::LoadFromDisk do
  subject(:save_to_hnswlib) { call_command }

  let(:params) do
    {
      base_dir_path: base_dir_path,
      index_file_path: index_file_path,
      json_doc_file_path: json_doc_file_path
    }
  end
  let(:base_dir_path) { '.' }
  let(:json_doc_file_path) { './spec/fixtures/embeddings/test_hnsw_index.json' }
  let(:index_file_path) { './spec/fixtures/embeddings/test_hnsw_index.bin' }

  it 'returns hnswlib type' do
    expect(save_to_hnswlib[:type]).to eq(:hnswlib)
  end

  it 'returns vector_store' do
    expect(save_to_hnswlib[:vector_store].size).to be_positive
  end

  it 'returns Boxcars::VectorStore::Document' do
    expected = save_to_hnswlib[:vector_store].map { |x| x.class.name }.uniq
    expect(expected).to eq(['Boxcars::VectorStore::Document'])
  end

  context 'when base_dir_path is nil' do
    let(:base_dir_path) { nil }

    it 'returns vector_store if files exist' do
      json_content = JSON.parse(File.read(json_doc_file_path), symbolize_names: true)
      expect(save_to_hnswlib[:vector_store].size).to eq(json_content.size)
    end

    context 'when files do not exist' do
      let(:json_doc_file_path) { './spec/fixtures/embeddings/does_not_exist.json' }
      let(:index_file_path) { './spec/fixtures/embeddings/does_not_exist.bin' }

      it 'raises an error' do
        expect { save_to_hnswlib }.to raise_error(Boxcars::ArgumentError)
      end
    end
  end

  def call_command
    described_class.call(params)
  end
end
