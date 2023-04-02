require 'spec_helper'
require 'json'

# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe Boxcars::Embeddings::SimilaritySearch do
  subject(:neighbors) { similarity_search.call(query: query) }

  let(:similarity_search) { described_class.new(embeddings: embeddings, vector_store: vector_store, openai_connection: openai_client) }
  let(:query) { 'how many implementations are there for hnswlib?' }
  let(:num_neighbors) { 2 }

  let(:paths) do
    {
      embeddings_file: 'spec/fixtures/embeddings/result.json',
      index_file: 'spec/fixtures/embeddings/test_hnsw_index'
    }
  end

  let(:vector_store) do
    search_index = Hnswlib::HierarchicalNSW.new(space: 'l2', dim: 1536)
    search_index.load_index(paths[:index_file])
    search_index
  end

  let(:embeddings) do
    JSON.parse(File.read(paths[:embeddings_file])).map.with_index do |(_id, text), index|
      { 'doc_id' => index, 'document' => text }
    end
  end
  let(:openai_client) { instance_double(OpenAI::Client) }

  before do
    allow(Boxcars::Embeddings::EmbedViaOpenAI).to receive(:call).with(texts: [query], openai_connection: openai_client) do |_params|
      JSON.parse(File.read('spec/fixtures/embeddings/text_to_vector.json'), symbolize_names: true)
    end
    allow(openai_client).to receive(:is_a?).with(OpenAI::Client).and_return(true)
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

    it 'has meaningful result' do
      expect(neighbors.first[:document]).to include('implmentation')
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
