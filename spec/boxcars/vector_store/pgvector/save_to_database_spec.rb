# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Boxcars::VectorStore::Pgvector::SaveToDatabase do
  subject(:save_to_database) { call_command }

  let(:arguments) do
    {
      pg_vectors: pg_vectors,
      database_url: db_url,
      table_name: table_name,
      embedding_column_name: embedding_column_name,
      content_column_name: content_column_name,
      metadata_column_name: metadata_column_name
    }
  end
  let(:db_url) { ENV['DATABASE_URL'] || 'postgres://postgres@localhost/boxcars_test' }
  let(:table_name) { 'items' }
  let(:embedding_column_name) { 'embedding' }
  let(:content_column_name) { 'content' }
  let(:metadata_column_name) { 'metadata' }
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

  before do
    create_items_table
    allow(PG::Connection).to receive(:new).and_return(conn)
    allow(ENV).to receive(:fetch).with('DATABASE_URL', nil).and_return(db_url)
  end

  after do
    conn.close
  end

  describe '#call' do
    it 'returns success' do
      expect(save_to_database).to eq(pg_vectors)
    end

    it 'saves vectors to database' do
      call_command

      sql = <<~SQL
        SELECT id, #{content_column_name}, #{embedding_column_name}, #{metadata_column_name}
        FROM #{table_name} ORDER BY id ASC
      SQL
      db_documents = conn.exec(sql).values.map do |row|
        id, content, embedding, metadata = row
        [id.to_i, content, embedding, metadata.symbolize_keys]
      end
      documents = pg_vectors.map do |doc|
        [doc.metadata[:id], doc.content, doc.embedding, doc.metadata]
      end

      expect(db_documents).to eq(documents)
    end

    context 'when there is no id in metadata' do
      let(:pg_vectors) do
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

      it 'returns success' do
        expect(save_to_database).to eq(pg_vectors)
      end

      it 'saves vectors to database in order' do
        call_command

        sql = <<~SQL
          SELECT id, #{content_column_name}, #{embedding_column_name}, #{metadata_column_name}
          FROM #{table_name} ORDER BY id ASC
        SQL
        db_documents = conn.exec(sql).values.map do |row|
          _id, content, embedding, metadata = row
          [content, embedding, metadata.symbolize_keys]
        end
        documents = pg_vectors.map do |doc|
          [doc.content, doc.embedding, doc.metadata]
        end

        expect(db_documents).to eq(documents)
      end
    end

    context 'when pg_vectors is not an array' do
      let(:pg_vectors) { 'not an array' }

      it 'raises ArgumentError for nil input_array parameter' do
        expect { call_command }.to raise_error(
          Boxcars::ArgumentError, 'pg_vectors must be an array'
        )
      end
    end

    context 'when pg_vectors are not Boxcars::VectorStore::Document' do
      let(:pg_vectors) do
        [
          { content: "hello", metadata: { a: 1 } },
          { content: "hi", metadata: { a: 1 } },
          { content: "bye", metadata: { a: 1 } },
          { content: "what's this", metadata: { a: 1 } }
        ]
      end

      it 'raises ArgumentError for nil input_array parameter' do
        expect { call_command }.to raise_error(
          Boxcars::ArgumentError, 'invalid vector_store'
        )
      end
    end

    context 'when DATABASE_URL is missing' do
      before do
        allow(conn).to receive(:status).and_return(false)
      end

      it 'raises ArgumentError for nil input_array parameter' do
        expect { call_command }.to raise_error(
          Boxcars::ArgumentError, 'PostgreSQL connection is not ok'
        )
      end
    end

    context 'when table does not exist' do
      let(:table_name) { 'no_table' }

      it 'raises ArgumentError for nil input_array parameter' do
        expect { call_command }.to raise_error(
          Boxcars::ArgumentError, "Table 'no_table' does not exist"
        )
      end
    end

    context 'when column does not exist' do
      let(:embedding_column_name) { 'no_column' }

      it 'raises ArgumentError for nil input_array parameter' do
        expect { call_command }.to raise_error(
          Boxcars::ArgumentError, "Column 'no_column' does not exist in table 'items'"
        )
      end
    end
  end

  def call_command
    described_class.call(arguments)
  end
end
