# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Boxcars::VectorStore::Hnswlib::LoadFromDisk do
  subject(:save_to_hnswlib) { call_command }

  let(:params) do
    {
      index_file_path: index_file_path,
      json_doc_file_path: json_doc_file_path
    }
  end
  let(:json_doc_file_path) { 'spec/fixtures/embeddings/test_doc_text_file.json' }
  let(:index_file_path) { 'spec/fixtures/embeddings/test_hnsw_index.bin' }

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

  def call_command
    described_class.call(params)
  end
end
