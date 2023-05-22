# frozen_string_literal: true

require 'spec_helper'
require 'hnswlib'
require 'json'

RSpec.describe Boxcars::VectorStore::Hnswlib::Search do
  subject(:search_result) do
    hnswlib_search.call(
      query_vector: query_vector,
      count: count
    )
  end

  let(:query_vector) { Array.new(1536) { 0 } }
  let(:hnswlib_search) do
    described_class.new(
      vector_documents: vector_documents
    )
  end
  let(:count) { 2 }
  let(:vector_documents) do
    Boxcars::VectorStore::Hnswlib::LoadFromDisk.call(
      base_dir_path: base_dir_path,
      index_file_path: index_file_path,
      json_doc_file_path: json_doc_file_path
    )
  end

  let(:base_dir_path) { '.' }
  let(:json_doc_file_path) { './spec/fixtures/embeddings/test_hnsw_index.json' }
  let(:index_file_path) { './spec/fixtures/embeddings/test_hnsw_index.bin' }

  describe '#call' do
    it 'returns an array' do
      expect(search_result).to be_a(Array)
    end

    it 'returns at most count results' do
      expect(search_result.size).to be <= 2
    end

    it 'returns results with the correct keys' do
      expect(search_result.first.keys).to eq([:document, :distance])
    end

    it 'returns results with distances sorted in ascending order' do
      distances = search_result.map { |result| result[:distance] }
      expect(distances).to eq(distances.sort)
    end

    context 'with multiple calls' do
      let(:first_search_result) do
        hnswlib_search.call(
          query_vector: cost_ratio_response,
          count: 1
        ).first[:document].content
      end
      let(:second_search_result) do
        hnswlib_search.call(
          query_vector: hnaswlib_response,
          count: 1
        ).first[:document].content
      end
      let(:cost_ratio_response) do
        JSON.parse(File.read('spec/fixtures/embeddings/query_vector_cost.json'), symbolize_names: true).first[:embedding]
      end
      let(:hnaswlib_response) do
        JSON.parse(File.read('spec/fixtures/embeddings/query_vector_hnswlib.json'), symbolize_names: true).first[:embedding]
      end

      it 'returns the different results' do
        expect(first_search_result).not_to eq(second_search_result)
      end

      it 'returns the correct results for the first query' do
        expected = first_search_result.include?('Cost Ratio of OpenAI embedding')
        expect(expected).to be_truthy
      end

      it 'returns the correct results for the second query' do
        expected = second_search_result.include?('Can work with custom user defined distances (C++)')
        expect(expected).to be_truthy
      end
    end

    context 'with wrong query vector' do
      let(:query_vector) { Array.new(100) { 0.0 } }

      it 'raises an argument error' do
        expect { search_result }.to raise_error(Boxcars::ArgumentError)
      end
    end
  end
end
