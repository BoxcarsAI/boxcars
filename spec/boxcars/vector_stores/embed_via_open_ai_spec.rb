# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Boxcars::VectorStores::EmbedViaOpenAI do
  subject(:embedding) { call_command }

  let(:arguments) do
    {
      texts: texts,
      client: openai_client
    }
  end
  let(:texts) { ['example text'] }
  let(:openai_client) { instance_double(OpenAI::Client) }

  before do
    allow(openai_client).to receive(:embeddings) do |_params|
      JSON.parse(File.read('spec/fixtures/embeddings/embeddings_response.json'))
    end
    allow(openai_client).to receive(:is_a?).with(OpenAI::Client).and_return(true)
  end

  describe '#call' do
    it 'returns array' do
      expect(embedding).to be_an(Array)
    end

    it 'returns an embedding for the given text' do
      expect(embedding.size).to eq(1)
    end
  end

  def call_command
    described_class.call(**arguments)
  end
end
