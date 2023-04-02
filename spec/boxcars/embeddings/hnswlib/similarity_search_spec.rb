require 'spec_helper'
require 'json'

# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe Boxcars::Embeddings::Hnswlib::SimilaritySearch do
  subject(:neighbors) { similarity_search.call(query_embedding) }

  let(:query_embedding) { Array.new(1536) { 0.5 } }
  let(:num_neighbors) { 2 }

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
  let(:embeddings) { vector_store_and_embeddings.last }

  let(:similarity_search) do
    described_class.new(vector_store: vector_store, document_embeddings: embeddings, num_neighbors: num_neighbors)
  end

  describe '#call' do
    it 'returns an array' do
      expect(neighbors).to be_a(Array)
    end

    it 'returns at most num_neighbors results' do
      expect(neighbors.size).to be <= num_neighbors
    end

    it 'returns results with the correct keys' do
      expect(neighbors.first.keys).to eq(%i[document distance])
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
