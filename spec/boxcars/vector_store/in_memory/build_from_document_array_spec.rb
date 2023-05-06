# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Boxcars::VectorStore::InMemory::BuildFromDocumentArray do
  subject(:result) { call_command }

  let(:arguments) do
    {
      embedding_tool: embedding_tool,
      documents: documents
    }
  end
  let(:embedding_tool) { :openai }

  let(:documents) do
    [
      { content: "hello", metadata: { a: 1 } },
      { content: "hi", metadata: { a: 1 } },
      { content: "bye", metadata: { a: 1 } },
      { content: "what's this", metadata: { a: 1 } }
    ]
  end
  let(:embeddings) do
    JSON.parse(File.read('spec/fixtures/embeddings/documents_embedding_for_in_memory.json'))
  end

  before do
    allow(Boxcars::VectorStore::EmbedViaOpenAI).to receive(:call).and_return(embeddings)
  end

  describe '#call' do
    context 'with valid parameters' do
      it 'returns in_memory type' do
        expect(result[:type]).to eq(:in_memory)
      end

      it 'returns same number of data as document size' do
        expect(result[:vector_store].size).to eq(documents.size)
      end

      it 'adds memory vectors to memory_vectors array' do
        result[:vector_store].each_with_index do |memory_vector, index|
          expect(memory_vector.content).to eq(documents[index][:content])
        end
      end

      it 'merges metadata' do
        result[:vector_store].each_with_index do |memory_vector, index|
          check = documents[index][:metadata].keys.all? { |k| memory_vector.metadata.key?(k) }
          expect(check).to be_truthy
        end
      end
    end

    context 'when documents is nil' do
      let(:documents) { nil }

      it 'raises ArgumentError for nil documents parameter' do
        expect { call_command }.to raise_error(
          Boxcars::ArgumentError, 'documents is nil'
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
