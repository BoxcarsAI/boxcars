# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Boxcars::VectorStore::Pgvector::Search do
  let(:search_result) do
    pgvector_search.call(
      query_vector: query_vector,
      count: count
    )
  end
  let(:pgvector_search) do
    described_class.new(
      vector_documents: vector_documents
    )
  end

  let(:query_vector) { [1.0, 2.0, 3.0] }
  let(:count) { 1 }
  let(:vector_documents) do
    {
      type: :pgvector,
      vector_store: vector_store
    }
  end
  let(:vector_store) do
    {
      database_url: db_url,
      table_name: table_name,
      embedding_column_name: embedding_column_name,
      content_column_name: content_column_name
    }
  end
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
  let(:db_url) { ENV['DATABASE_URL'] || 'postgres://postgres@localhost/boxcars_test' }

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
  end

  after do
    conn.close
  end

  describe '#call' do
    it 'returns an array' do
      expect(search_result).to be_a(Array)
    end

    it 'returns the most similar document' do
      expect(search_result.first[:document].content).to eq(pg_vectors.first.content)
    end

    context 'when count is greater than 1' do
      let(:count) { 2 }

      it 'returns count number of documents' do
        expect(search_result.size).to eq(2)
      end

      it 'returns the most array of documents' do
        expect(search_result.map { |x| x[:distance] }).to eq([0.0, 5.196152422706632])
      end
    end

    context 'when table does not exist' do
      let(:table_name) { 'no_table' }

      it 'raises an error' do
        expect { search_result }.to raise_error(
          Boxcars::ArgumentError, "Table 'no_table' does not exist"
        )
      end
    end

    context 'when DATABASE_URL is missing' do
      before do
        allow(conn).to receive(:status).and_return(false)
      end

      it 'raises an error' do
        expect { search_result }.to raise_error(
          Boxcars::ArgumentError, 'PostgreSQL connection is not ok'
        )
      end
    end

    context 'when column does not exist' do
      let(:embedding_column_name) { 'no_column' }

      it 'raises an error' do
        expect { search_result }.to raise_error(
          Boxcars::ArgumentError, "Column 'no_column' does not exist in table 'items'"
        )
      end
    end

    context 'with empty query_vector' do
      let(:query_vector) { [] }

      it 'raises an error' do
        expect { search_result }.to raise_error(
          Boxcars::ArgumentError, 'query_vector is empty'
        )
      end
    end
  end

  def call_command
    described_class.call(arguments)
  end
end
