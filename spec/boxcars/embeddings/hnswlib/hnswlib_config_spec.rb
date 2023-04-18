# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/MultipleExpectations
# rubocop:disable RSpec/ExampleLength
RSpec.describe Boxcars::Embeddings::Hnswlib::HnswlibConfig do
  subject(:config) { described_class.new(**args) }

  let(:args) { {} }

  describe '#initialize' do
    context 'when initialized with default arguments' do
      it 'sets default values' do
        expect(config.metric).to eq('l2')
        expect(config.max_item).to eq(10_000)
        expect(config.dim).to eq(2)
        expect(config.ef_construction).to eq(200)
        expect(config.space).to eq('l2')
      end
    end

    context 'when initialized with custom arguments' do
      let(:args) do
        {
          metric: 'dot',
          max_item: 20_000,
          dim: 5,
          ef_construction: 300,
          max_outgoing_connection: 32
        }
      end

      it 'sets custom values' do
        expect(config.metric).to eq('dot')
        expect(config.max_item).to eq(20_000)
        expect(config.dim).to eq(5)
        expect(config.ef_construction).to eq(300)
        expect(config.space).to eq('ip')
      end
    end
  end

  describe '#to_json' do
    let(:args) do
      {
        metric: 'dot',
        max_item: 20_000,
        dim: 5,
        ef_construction: 300,
        max_outgoing_connection: 32
      }
    end

    it 'returns a JSON representation of the config' do
      json = JSON.parse(config.to_json)

      expect(json['metric']).to eq('dot')
      expect(json['max_item']).to eq(20_000)
      expect(json['dim']).to eq(5)
      expect(json['ef_construction']).to eq(300)
      expect(json['max_outgoing_connection']).to eq(32)
    end
  end
  # rubocop:enable RSpec/MultipleExpectations
  # rubocop:enable RSpec/ExampleLength
end
