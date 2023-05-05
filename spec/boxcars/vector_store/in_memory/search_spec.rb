# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Boxcars::VectorStore::InMemory::Search do
  let(:search_result) { call_command }
  let(:arguments) do
    {
      vector_documents: vector_documents,
      query: query,
      embedding_tool: embedding_tool
    }
  end
  let(:vector_documents) do
    [
      { document: { page_content: "hello", metadata: { a: 1 } }, vector: [1.0, 2.0, 3.0] },
      { document: { page_content: "hi", metadata: { a: 1 } }, vector: [4.0, 5.0, 6.0] },
      { document: { page_content: "bye", metadata: { a: 1 } }, vector: [7.0, 8.0, 9.0] },
      { document: { page_content: "what's this", metadata: { a: 1 } }, vector: [10.0, 11.0, 12.0] },
    ]
  end
  let(:query) { "hello" }
  let(:embedding_tool) { :openai }

  before do
    allow(ENV).to receive(:fetch).with('OPENAI_API_KEY', nil).and_return('mock_api_key')
    allow(Boxcars::VectorStore::EmbedViaOpenAI).to receive(:call).and_return([[1.0, 2.0, 3.0]])
  end

  describe '#call' do
    context 'with valid parameters' do
      it 'returns the most similar document' do
        expect(search_result).to eq(vector_documents.first)
      end
    end

    context 'when embedding_tool is not one of the supported tools' do
      let(:embedding_tool) { :not_supported }

      it 'raises an error' do
        expect { call_command }.to raise_error(
          Boxcars::ArgumentError, 'embedding_tool is invalid'
        )
      end
    end

    context 'when query is empty' do
      let(:query) { '' }

      it 'raises an error' do
        expect { call_command }.to raise_error(
          Boxcars::ArgumentError, 'query is empty'
        )
      end
    end

    context 'when vector_documents is nil' do
      let(:vector_documents) { nil }

      it 'raises an error but returns nil as embeddings_method' do
        expect { call_command }.to raise_error(
          Boxcars::ArgumentError, 'vector_documents is not valid'
        )
      end
    end

    context 'when vector_documents is not an array of hashes with :document and :vector keys' do
      let(:embedding_tool) { :openai }
      let(:vector_documents) { [1, 2, 3] }

      it 'raises ArgumentError for invalid vector_documents parameter' do
        expect { search_result }.to raise_error(
          Boxcars::ArgumentError, "vector_documents is not valid"
        )
      end
    end
  end

  def call_command
    described_class.call(**arguments)
  end
end
