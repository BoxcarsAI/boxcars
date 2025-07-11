# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Boxcars::VectorStore::Pgvector::BuildFromArray do
  subject(:result) { call_command }

  before(:all) do
    unless Gem.loaded_specs.key?('pgvector') && Gem.loaded_specs.key?('pg')
      skip "pgvector and pg gems not available, skipping pgvector tests"
    end
  end

  let(:arguments) do
    {
      embedding_tool: embedding_tool,
      input_array: input_array,
      database_url: db_url,
      table_name: table_name,
      embedding_column_name: embedding_column_name,
      content_column_name: content_column_name,
      metadata_column_name: metadata_column_name
    }
  end

  let(:embedding_tool) { :openai }
  let(:db_url) { ENV['DATABASE_URL'] || 'postgres://postgres@localhost/boxcars_test' }
  let(:table_name) { 'items' }
  let(:embedding_column_name) { 'embedding' }
  let(:content_column_name) { 'content' }
  let(:metadata_column_name) { 'metadata' }
  let(:input_array) do
    [
      { content: "hello", metadata: { a: 1 } },
      { content: "hi", metadata: { a: 1 } },
      { content: "bye", metadata: { a: 1 } },
      { content: "what's this", metadata: { a: 1 } }
    ]
  end
  let(:documents) do
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
  let(:embeddings) do
    JSON.parse(File.read('spec/fixtures/embeddings/documents_embedding_for_in_memory.json'))
  end

  before do
    allow(Boxcars::VectorStore::Pgvector::SaveToDatabase).to receive(:call).and_return(documents)
  end

  describe '#call' do
    context 'with valid parameters' do
      it 'returns in_memory type' do
        VCR.use_cassette("vector_store/pgvector/build_from_array_1") do
          expect(result[:type]).to eq(:pgvector)
        end
      end

      it 'returns same number of data as document size' do
        VCR.use_cassette("vector_store/pgvector/build_from_array_2") do
          expect(result[:vector_store].size).to eq(input_array.size)
        end
      end

      it 'adds memory vectors to memory_vectors array' do
        VCR.use_cassette("vector_store/pgvector/build_from_array_3") do
          result[:vector_store].each_with_index do |memory_vector, index|
            expect(memory_vector.content).to eq(input_array[index][:content])
          end
        end
      end

      it 'merges metadata' do
        VCR.use_cassette("vector_store/pgvector/build_from_array_4") do
          result[:vector_store].each_with_index do |memory_vector, index|
            check = input_array[index][:metadata].keys.all? { |k| memory_vector.metadata.key?(k) }
            expect(check).to be_truthy
          end
        end
      end
    end

    context 'when input_array is nil' do
      let(:input_array) { nil }

      it 'raises ArgumentError for nil input_array parameter' do
        expect { call_command }.to raise_error(
          Boxcars::ArgumentError, 'input_array is nil'
        )
      end
    end

    context 'when input_array has wrong type' do
      let(:input_array) { 'not an array' }

      it 'raises ArgumentError for invalid input_array parameter' do
        expect { call_command }.to raise_error(
          Boxcars::ArgumentError, 'input_array must be an array'
        )
      end
    end

    context 'when input_array has wrong keys' do
      let(:input_array) do
        [
          { data: "hello", metadata: { a: 1 } },
          { data: "hi", metadata: { a: 1 } },
          { data: "bye", metadata: { a: 1 } },
          { data: "what's this", metadata: { a: 1 } }
        ]
      end

      it 'raises ArgumentError for invalid input_array parameter' do
        expect { call_command }.to raise_error(
          Boxcars::ArgumentError, 'items in input_array needs to have content and metadata'
        )
      end
    end

    context 'when embedding_tool is not one of the supported tools' do
      let(:embedding_tool) { :not_supported }

      it 'raises ArgumentError for invalid embedding_tool parameter' do
        expect { call_command }.to raise_error(
          Boxcars::ArgumentError, 'embedding_tool is invalid'
        )
      end
    end

    def call_command
      described_class.call(**arguments)
    end
  end
end
