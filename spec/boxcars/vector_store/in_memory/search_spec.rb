# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Boxcars::VectorStore::InMemory::Search do
  let(:search_result) do
    in_memory_search.call(
      query_vector: query_vector,
      count: count
    )
  end
  let(:in_memory_search) do
    described_class.new(
      vector_documents: vector_documents
    )
  end
  let(:query_vector) { [1.0, 2.0, 3.0] }
  let(:count) { 1 }
  let(:vector_documents) do
    {
      type: :in_memory,
      vector_store: vector_store
    }
  end

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

  before do
    allow(Boxcars::VectorStore::EmbedViaOpenAI).to receive(:call).and_return([[1.0, 2.0, 3.0]])
  end

  describe '#call' do
    context 'with valid parameters' do
      it 'returns the most similar document' do
        expect(search_result.first[:document].content).to eq(vector_store.first.content)
      end
    end

    context 'when count is greater than 1' do
      let(:count) { 2 }

      it 'returns the most array of documents' do
        expect(search_result.map { |x| x[:document].content }).to eq(%w[hello hi])
      end
    end

    context 'with only necessary parameters' do
      let(:arguments) do
        {
          vector_documents: vector_documents,
          query: query
        }
      end

      it 'returns the most similar document' do
        expect(search_result.first[:similarity]).to eq(1.0)
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

    context 'with wrong query vector' do
      let(:query_vector) { Array.new(100) { 0.0 } }

      it 'raises an argument error' do
        expect { search_result }.to raise_error(Boxcars::ArgumentError)
      end
    end

    context 'when vector_documents is nil' do
      let(:vector_documents) { nil }

      it 'raises an error but returns nil as embeddings_method' do
        expect { search_result }.to raise_error(
          Boxcars::ArgumentError, 'vector_documents is not valid'
        )
      end
    end

    context 'when vector_documents[:vector_store] is not an array of hashes with :document and :vector keys' do
      let(:embedding_tool) { :openai }
      let(:vector_documents) do
        {
          type: :in_memory,
          vector_store: vector_store
        }
      end
      let(:vector_store) { [1, 2, 3] }

      it 'raises ArgumentError for invalid vector_documents parameter' do
        expect { search_result }.to raise_error(
          Boxcars::ArgumentError, "vector_documents is not valid"
        )
      end
    end
  end
end
