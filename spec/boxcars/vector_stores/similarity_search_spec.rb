require 'spec_helper'
require 'json'

# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe Boxcars::VectorStores::SimilaritySearch do
  subject(:neighbors) { similarity_search.call(query: query) }

  let(:similarity_search) do
    described_class.new(
      embeddings: json_doc_path,
      vector_store: vector_store,
      openai_connection: openai_client
    )
  end
  let(:query) { 'how many implementations are there for hnswlib?' }
  let(:num_neighbors) { 2 }
  let(:json_doc_path) { 'spec/fixtures/embeddings/test_doc_text_file.json' }
  let(:index_path) { 'spec/fixtures/embeddings/test_hnsw_index' }
  let(:vector_store) do
    search_index = Hnswlib::HierarchicalNSW.new(space: 'l2', dim: 1536)
    search_index.load_index(index_path)
    search_index
  end
  let(:openai_client) { instance_double(OpenAI::Client) }

  before do
    allow(Boxcars::VectorStores::EmbedViaOpenAI).to receive(:call).with(texts: [query], openai_connection: openai_client) do |_params|
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
