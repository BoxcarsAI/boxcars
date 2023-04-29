# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Boxcars::VectorStores::InMemory::AddDocuments do
  subject(:vector_documents) { call_command }

  let(:arguments) do
    {
      embedding_tool: :openai,
      documents: documents
    }
  end
  let(:embeddings) do
    JSON.parse(File.read('spec/fixtures/embeddings/documents_embedding_for_in_memory.json'))
  end
  let(:openai_client) { instance_double(OpenAI::Client) }

  let(:documents) do
    [
      { page_content: "hello", metadata: { a: 1 } },
      { page_content: "hi", metadata: { a: 1 } },
      { page_content: "bye", metadata: { a: 1 } },
      { page_content: "what's this", metadata: { a: 1 } },
    ]
  end

  before do
    allow(ENV).to receive(:fetch).with('OPENAI_API_KEY', nil).and_return('mock_api_key')
    allow(Boxcars::VectorStores::EmbedViaOpenAI).to receive(:call).and_return(embeddings)
  end

  describe '#call' do
    context 'with valid parameters' do
      # rubocop:disable RSpec/MultipleExpectations
      # rubocop:disable RSpec/ExampleLength
      xit 'adds documents with vectors' do
        expect(vector_documents).to be_an(Array)
        expect(vector_documents.size).to eq(documents.size)

        vector_documents.each_with_index do |vector_document, index|
          expect(vector_document).to be_a(Hash)
          expect(vector_document[:document]).to be_a(Boxcars::VectorStores::Document)
          expect(vector_document[:document].page_content).to eq(documents[index][:page_content])
          expect(vector_document[:vector]).to be_an(Array)
        end
      end
      # rubocop:enable RSpec/MultipleExpectations
      # rubopcop:enable RSpec/ExampleLength
    end

    context 'with invalid parameters' do
      xit 'raises ArgumentError for invalid embeddings parameter' do
        expect { described_class.new('invalid_parameter') }.to raise_error(ArgumentError, "embeddings must be an instance of Boxcars::VectorStores::EmbedViaOpenAI")
      end
    end
  end

  def call_command
    described_class.call(**arguments)
  end
end
