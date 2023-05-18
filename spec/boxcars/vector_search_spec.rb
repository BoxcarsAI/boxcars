# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe Boxcars::VectorSearch do
  subject(:search_result) do
    vector_search.call(
      query: query,
      count: num_neighbors
    )
  end

  let(:vector_search) do
    described_class.new(
      vector_documents: vector_documents,
      openai_connection: openai_client
    )
  end
  let(:query) { 'how many implementations are there for hnswlib?' }
  let(:openai_client) { instance_double(OpenAI::Client) }
  let(:query_vector) do
    JSON.parse(File.read('spec/fixtures/embeddings/query_vector.json'), symbolize_names: true)
  end

  describe '#call' do
    context 'with hnswlib search' do
      let(:num_neighbors) { 2 }
      let(:vector_documents) do
        Boxcars::VectorStore::Hnswlib::LoadFromDisk.call(
          index_file_path: hnswlib_index,
          json_doc_file_path: json_doc
        )
      end

      let(:json_doc) { 'spec/fixtures/embeddings/test_doc_text_file.json' }
      let(:hnswlib_index) { 'spec/fixtures/embeddings/test_hnsw_index.bin' }

      before do
        allow(Boxcars::VectorStore::EmbedViaOpenAI).to receive(:call).and_return(query_vector)
      end

      it 'returns an Document array' do
        expect(search_result).to be_a(Array)

        expect(search_result.first[:document]).to be_a(Boxcars::VectorStore::Document)
      end

      it 'returns at most num_neighbors results' do
        expect(search_result.size).to be <= num_neighbors
      end

      it 'returns results with the correct keys' do
        expect(search_result.first.keys).to eq(%i[document distance])
      end

      it 'has meaningful result' do
        content = search_result.first[:document].content

        expect(content).to include('implementation')
      end
    end

    context 'with in memory search' do
      let(:vector_documents) do
        {
          type: vector_store_type,
          vector_store: vector_store,
          json_doc: nil
        }
      end
      let(:vector_store_type) { :in_memory }
      let(:vector_store) do
        [
          Boxcars::VectorStore::Document.new(
            content: "hello", metadata: { a: 1 }, embedding: [1.0, 2.0, 3.0]
          ),
          Boxcars::VectorStore::Document.new(
            content: "hi", metadata: { a: 1 }, embedding: [4.0, 5.0, 6.0]
          ),
          Boxcars::VectorStore::Document.new(
            content: "bye", metadata: { a: 1 }, embedding: [7.0, 8.0, 9.0]
          ),
          Boxcars::VectorStore::Document.new(
            content: "what's this", metadata: { a: 1 }, embedding: [10.0, 11.0, 12.0]
          )
        ]
      end
      let(:num_neighbors) { 1 }
      let(:query_vector) { [{ embedding: [1.0, 2.0, 3.0] }] }

      before do
        allow(Boxcars::VectorStore::EmbedViaOpenAI).to receive(:call).and_return(query_vector)
      end

      it 'returns an Document array' do
        expect(search_result).to be_a(Array)

        expect(search_result.first[:document]).to be_a(Boxcars::VectorStore::Document)
      end

      it 'returns the most similar document' do
        expect(search_result.first[:document].content).to eq(vector_store.first.content)
      end

      context 'when count is greater than 1' do
        let(:num_neighbors) { 2 }

        it 'returns the most array of documents' do
          expect(search_result.map { |x| x[:document].content }).to eq(%w[hello hi])
        end
      end
    end

    context 'with pgvector search' do
      let(:vector_documents) do
        {
          type: vector_store_type,
          vector_store: vector_store
        }
      end
      let(:vector_store_type) { :pgvector }
      let(:vector_store) do
        {
          database_url: db_url,
          table_name: table_name,
          embedding_column_name: embedding_column_name,
          content_column_name: content_column_name
        }
      end
      let(:db_url) { ENV['DATABASE_URL'] || 'postgres://postgres@localhost/boxcars_test' }
      let(:table_name) { 'items' }
      let(:embedding_column_name) { 'embedding' }
      let(:content_column_name) { 'content' }
      let(:pg_vectors) do
        [
          Boxcars::VectorStore::Document.new(
            content: "hello", metadata: { a: 1, id: 1 }, embedding: [1.0, 2.0, 3.0]
          ),
          Boxcars::VectorStore::Document.new(
            content: "hi", metadata: { a: 1, id: 2 }, embedding: [4.0, 5.0, 6.0]
          ),
          Boxcars::VectorStore::Document.new(
            content: "bye", metadata: { a: 1, id: 3 }, embedding: [7.0, 8.0, 9.0]
          ),
          Boxcars::VectorStore::Document.new(
            content: "what's this", metadata: { a: 1, id: 4 }, embedding: [10.0, 11.0, 12.0]
          )
        ]
      end
      let(:num_neighbors) { 1 }
      let(:query_vector) { [{ embedding: [1.0, 2.0, 3.0] }] }

      before do
        create_items_table
        add_vectors_to_database(
          documents: pg_vectors,
          table_name: 'items',
          embedding_column_name: 'embedding',
          content_column_name: 'content',
          metadata_column_name: 'metadata'
        )
        allow(PG::Connection).to receive(:new).and_return(conn)
        allow(Boxcars::VectorStore::EmbedViaOpenAI).to receive(:call).and_return(query_vector)
      end

      it 'returns an Document array' do
        expect(search_result).to be_a(Array)

        expect(search_result.first[:document]).to be_a(Boxcars::VectorStore::Document)
      end

      it 'returns the most similar document' do
        expect(search_result.first[:document].content).to eq(pg_vectors.first.content)
      end

      context 'when count is greater than 1' do
        let(:num_neighbors) { 2 }

        it 'returns the most array of documents' do
          expect(search_result.map { |x| x[:document].content }).to eq(%w[hello hi])
        end
      end
    end
  end
end
