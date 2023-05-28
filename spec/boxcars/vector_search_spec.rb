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
  let(:query) { 'custom user defined distances' }
  let(:openai_client) { instance_double(OpenAI::Client) }
  let(:query_vector) do
    JSON.parse(File.read('spec/fixtures/embeddings/query_vector.json'), symbolize_names: true)
  end

  describe '#call' do
    context 'with hnswlib search' do
      let(:num_neighbors) { 1 }
      let(:vector_documents) do
        Boxcars::VectorStore::Hnswlib::LoadFromDisk.call(
          base_dir_path: base_dir_path,
          index_file_path: hnswlib_index,
          json_doc_file_path: json_doc
        )
      end

      let(:base_dir_path) { '.' }
      let(:json_doc) { './spec/fixtures/embeddings/test_hnsw_index.json' }
      let(:hnswlib_index) { './spec/fixtures/embeddings/test_hnsw_index.bin' }

      before do
        allow(Boxcars::VectorStore::EmbedViaOpenAI).to receive(:call)
          .with(texts: [query], client: openai_client)
          .and_return(query_vector)
      end

      it 'returns an Document array' do
        expect(search_result).to be_a(Array)

        expect(search_result.first[:document]).to be_a(Boxcars::VectorStore::Document)
      end

      it 'returns num_neighbors results' do
        expect(search_result.size).to eq(num_neighbors)
      end

      it 'returns results with the correct keys' do
        expect(search_result.first.keys).to eq(%i[document distance])
      end

      it 'has meaningful result' do
        content = search_result.first[:document].content

        expect(content).to include('implementation')
      end

      context 'with multiple calls' do
        let(:first_search_result) do
          vector_search.call(
            query: question_one,
            count: 1
          ).first[:document].content
        end

        let(:second_search_result) do
          vector_search.call(
            query: question_two,
            count: 1
          ).first[:document].content
        end

        let(:vector_search) do
          described_class.new(
            vector_documents: vector_documents,
            openai_connection: openai_client
          )
        end

        let(:question_one) { 'Tell me about the cost ratio of OpenAI embedding' }
        let(:question_two) { 'What should do for user defined distances when I use Hnswlib' }
        let(:cost_ratio_response) do
          JSON.parse(File.read('spec/fixtures/embeddings/query_vector_cost.json'), symbolize_names: true)
        end
        let(:hnaswlib_response) do
          JSON.parse(File.read('spec/fixtures/embeddings/query_vector_hnswlib.json'), symbolize_names: true)
        end

        let(:openai_client) { instance_double(OpenAI::Client) }

        before do
          allow(Boxcars::VectorStore::EmbedViaOpenAI).to receive(:call).
            with(texts: [question_one], client: openai_client).
            and_return(cost_ratio_response)

          allow(Boxcars::VectorStore::EmbedViaOpenAI).to receive(:call)
            .with(texts: [question_two], client: openai_client)
            .and_return(hnaswlib_response)
        end

        it 'returns the correct results for the first query' do
          expect(first_search_result).to include('Cost Ratio of OpenAI embedding to Self-Hosted embedding')
        end

        it 'returns the correct results for the second query' do
          expect(second_search_result).to include('Can work with custom user defined distances (C++)')
        end

        it 'returns different results with the same search instace' do
          expect(first_search_result).not_to eq(second_search_result)
        end
      end
    end

    context 'with in memory search' do
      let(:vector_documents) do
        {
          type: vector_store_type,
          vector_store: vector_store
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
