require 'spec_helper'
require 'json'

RSpec.describe Boxcars::Embeddings::Hnswlib::HnswlibSearch do
  subject(:neighbors) { hnswlib_search.call(query_embedding) }

  let(:hnswlib_search) do
    described_class.new(
      vector_store: vector_store,
      options: { json_doc_path: json_doc_path, num_neighbors: 2 }
    )
  end
  let(:json_doc_path) { 'spec/fixtures/embeddings/test_doc_text_file.json' }
  let(:query_embedding) { Array.new(1536) { 0.2 } }

  let(:vector_store_and_embeddings) do
    embeddings_file = 'spec/fixtures/embeddings/result.json'
    index_file = 'spec/fixtures/embeddings/test_hnsw_index'

    embeddings = JSON.parse(File.read(embeddings_file)).map.with_index do |(_id, text), index|
      { 'doc_id' => index, 'document' => text }
    end

    search_index = Hnswlib::HierarchicalNSW.new(space: 'l2', dim: 1536)
    search_index.load_index(index_file)

    [search_index, embeddings]
  end
  let(:vector_store) { vector_store_and_embeddings.first }

  describe '#call' do
    it 'returns an array' do
      expect(neighbors).to be_a(Array)
    end

    it 'returns at most num_neighbors results' do
      expect(neighbors.size).to be <= 2
    end

    it 'returns results with the correct keys' do
      expect(neighbors.first.keys).to eq([:document, :distance])
    end

    it 'returns results with distances sorted in ascending order' do
      distances = neighbors.map { |result| result[:distance] }
      expect(distances).to eq(distances.sort)
    end
  end
end
