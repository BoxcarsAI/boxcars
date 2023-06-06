# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Boxcars::VectorStore::InMemory::BuildFromArray do
  subject(:result) { call_command }

  let(:arguments) do
    {
      embedding_tool: embedding_tool,
      documents: input_array
    }
  end
  let(:embedding_tool) { :openai }

  let(:input_array) do
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

  describe '#call' do
    context 'with valid parameters' do
      it 'returns in_memory type' do
        VCR.use_cassette("vector_store/in_memory/build_from_array_1") do
          expect(result[:type]).to eq(:in_memory)
        end
      end

      it 'returns same number of data as document size' do
        VCR.use_cassette("vector_store/in_memory/build_from_array_2") do
          expect(result[:vector_store].size).to eq(input_array.size)
        end
      end

      it 'adds memory vectors to memory_vectors array' do
        VCR.use_cassette("vector_store/in_memory/build_from_array_3") do
          result[:vector_store].each_with_index do |memory_vector, index|
            expect(memory_vector.content).to eq(input_array[index][:content])
          end
        end
      end

      it 'merges metadata' do
        VCR.use_cassette("vector_store/in_memory/build_from_array_4") do
          result[:vector_store].each_with_index do |memory_vector, index|
            check = input_array[index][:metadata].keys.all? { |k| memory_vector.metadata.key?(k) }
            expect(check).to be_truthy
          end
        end
      end
    end

    context 'when documents is nil' do
      let(:input_array) { nil }

      it 'raises ArgumentError for nil documents parameter' do
        expect { call_command }.to raise_error(
          Boxcars::ArgumentError, 'documents is nil'
        )
      end
    end

    context 'when documents has wrong type' do
      let(:input_array) { 'not an array' }

      it 'raises ArgumentError for invalid documents parameter' do
        expect { call_command }.to raise_error(
          Boxcars::ArgumentError, 'documents must be an array'
        )
      end
    end

    context 'when documents has wrong keys' do
      let(:input_array) do
        [
          { data: "hello", metadata: { a: 1 } },
          { data: "hi", metadata: { a: 1 } },
          { data: "bye", metadata: { a: 1 } },
          { data: "what's this", metadata: { a: 1 } }
        ]
      end

      it 'raises ArgumentError for invalid documents parameter' do
        expect { call_command }.to raise_error(
          Boxcars::ArgumentError, 'items in documents needs to have content and metadata'
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
