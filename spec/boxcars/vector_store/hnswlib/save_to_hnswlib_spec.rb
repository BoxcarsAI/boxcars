# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Boxcars::VectorStore::Hnswlib::SaveToHnswlib do
  subject(:save_to_hnswlib) { call_command }

  let(:hnsw_vectors) do
    [
      Boxcars::VectorStore::Document.new(
        content: "Document 0", embedding: [0.1, 0.2], metadata: { doc_id: 0 }.merge(metadata_part)
      ),
      Boxcars::VectorStore::Document.new(
        content: "Document 1", embedding: [0.3, 0.4], metadata: { doc_id: 1 }.merge(metadata_part)
      ),
      Boxcars::VectorStore::Document.new(
        content: "Document 2", embedding: [0.5, 0.6], metadata: { doc_id: 2 }.merge(metadata_part)
      )
    ]
  end
  let(:metadata_part) do
    {
      dim: 2,
      index_file_path: File.join(Dir.tmpdir, 'test_hnsw_index2.bin'),
      json_doc_file_path: File.join(Dir.tmpdir, 'test_doc_texts.json')
    }
  end

  let(:test_file_paths) do
    {
      index_file_path: File.join(Dir.tmpdir, 'test_hnsw_index2.bin'),
      json_doc_file_path: File.join(Dir.tmpdir, 'test_doc_texts.json')
    }
  end

  before do
    FileUtils.rm_f(test_file_paths[:index_file_path])
    FileUtils.rm_f(test_file_paths[:json_doc_file_path])
  end

  after do
    FileUtils.rm_f(test_file_paths[:index_file_path])
    FileUtils.rm_f(test_file_paths[:json_doc_file_path])
  end

  describe '#call' do
    it 'saves the index and document texts to the specified paths' do
      expect(File.exist?(test_file_paths[:index_file_path])).to be(false)
      expect(File.exist?(test_file_paths[:json_doc_file_path])).to be(false)

      save_to_hnswlib

      expect(File.exist?(test_file_paths[:index_file_path])).to be(true)
      expect(File.exist?(test_file_paths[:json_doc_file_path])).to be(true)
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

  def call_command
    described_class.call(hnsw_vectors)
  end
end
