# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/ExampleLength
# rubocop:disable RSpec/MultipleMemoizedHelpers
# rubocop:disable RSpec/MultipleExpectations
RSpec.describe Boxcars::VectorStores::Hnswlib::SaveToHnswlib do
  subject(:save_to_hnswlib) { call_command }

  let(:document_embeddings) do
    [
      { doc_id: 0, embedding: [0.1, 0.2], document: "Document 0" },
      { doc_id: 1, embedding: [0.3, 0.4], document: "Document 1" },
      { doc_id: 2, embedding: [0.5, 0.6], document: "Document 2" }
    ]
  end
  let(:hnswlib_config) do
    Boxcars::VectorStores::Hnswlib::HnswlibConfig.new(
      metric: "l2", max_item: 10000, dim: 2
    )
  end
  let(:hnswlib_config_json) { File.join(Dir.tmpdir, 'hnswlib_config.json') }
  let(:test_file_paths) do
    {
      index_file_path: File.join(Dir.tmpdir, 'test_hnsw_index2.bin'),
      json_doc_file_path: File.join(Dir.tmpdir, 'test_doc_texts.json')
    }
  end

  after do
    FileUtils.rm_f(test_file_paths[:index_file_path])
    FileUtils.rm_f(test_file_paths[:json_doc_file_path])
    FileUtils.rm_f(hnswlib_config_json)
  end

  describe '#call' do
    it 'saves the index and document texts to the specified paths' do
      expect(File.exist?(test_file_paths[:index_file_path])).to be(false)
      expect(File.exist?(test_file_paths[:json_doc_file_path])).to be(false)

      save_to_hnswlib

      expect(File.exist?(test_file_paths[:index_file_path])).to be(true)
      expect(File.exist?(test_file_paths[:json_doc_file_path])).to be(true)
      expect(File.exist?(hnswlib_config_json)).to be(true)
    end
  end

  describe 'integration with Hnswlib' do
    let(:loaded_index) do
      index = Hnswlib::HierarchicalNSW.new(space: 'l2', dim: 2)
      index.load_index(test_file_paths[:index_file_path])
      index
    end
    let(:query_embedding) { [0.15, 0.25] }

    before do
      save_to_hnswlib
    end

    it 'adds embeddings to the index and retrieves the nearest neighbor correctly' do
      nearest_neighbors = loaded_index.search_knn(query_embedding, 2)

      expect(nearest_neighbors.length).to eq(2)
      expect(nearest_neighbors[0][0]).to eq(0)
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers
  # rubocop:enable RSpec/ExampleLength
  # rubocop:enable RSpec/MultipleExpectations

  def call_command
    described_class.call(
      document_embeddings: document_embeddings,
      hnswlib_config: hnswlib_config,
      **test_file_paths
    )
  end
end
