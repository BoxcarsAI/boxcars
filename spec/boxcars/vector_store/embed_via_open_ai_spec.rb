# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Boxcars::VectorStore::EmbedViaOpenAI do
  subject(:embedding) { call_command }

  let(:arguments) do
    {
      texts: texts,
      client: openai_client
    }
  end
  let(:texts) { ['example text'] }
  let(:openai_client) { double('OpenAIClient') } # rubocop:disable RSpec/VerifiedDoubles

  before do
    allow(openai_client).to receive(:respond_to?).with(:embeddings_create).and_return(false)
    allow(openai_client).to receive(:respond_to?).with(:embeddings).and_return(true)
    allow(openai_client).to receive(:embeddings) do |_params|
      JSON.parse(File.read('spec/fixtures/embeddings/embeddings_response.json'))
    end
  end

  describe '#call' do
    it 'returns array' do
      expect(embedding).to be_an(Array)
    end

    it 'returns an embedding for the given text' do
      expect(embedding.size).to eq(1)
    end

    it 'supports adapter clients with embeddings_create' do
      adapter_client = double('OpenAIAdapterClient') # rubocop:disable RSpec/VerifiedDoubles
      allow(adapter_client).to receive(:respond_to?).with(:embeddings_create).and_return(true)
      allow(adapter_client).to receive(:embeddings_create) do |_params|
        JSON.parse(File.read('spec/fixtures/embeddings/embeddings_response.json'))
      end

      result = described_class.call(texts: texts, client: adapter_client)

      expect(result.size).to eq(1)
      expect(result.first[:embedding]).to be_an(Array)
    end
  end

  def call_command
    described_class.call(**arguments)
  end
end
