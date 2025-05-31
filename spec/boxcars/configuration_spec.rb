# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Boxcars::Configuration do
  let(:configuration) { described_class.new }

  describe '#default_model' do
    it 'can be set and retrieved' do
      configuration.default_model = 'gpt-4o'
      expect(configuration.default_model).to eq('gpt-4o')
    end

    it 'defaults to nil' do
      expect(configuration.default_model).to be_nil
    end
  end

  describe 'Boxcars.configure' do
    after do
      # Reset configuration after each test
      Boxcars.configuration.default_model = nil
    end

    it 'allows setting default_model through configuration block' do
      Boxcars.configure do |config|
        config.default_model = 'claude-sonnet-4-0'
      end

      expect(Boxcars.configuration.default_model).to eq('claude-sonnet-4-0')
    end
  end

  describe 'Boxcars::Engines.engine with configuration' do
    after do
      # Reset configuration after each test
      Boxcars.configuration.default_model = nil
    end

    it 'uses configured default_model when no model specified' do
      Boxcars.configuration.default_model = 'gpt-4o'

      allow(Boxcars::Openai).to receive(:new)
      Boxcars::Engines.engine
      expect(Boxcars::Openai).to have_received(:new).with(model: 'gpt-4o')
    end

    it 'falls back to DEFAULT_MODEL when default_model is nil' do
      Boxcars.configuration.default_model = nil

      allow(Boxcars::GeminiAi).to receive(:new)
      Boxcars::Engines.engine
      expect(Boxcars::GeminiAi).to have_received(:new).with(model: Boxcars::Engines::DEFAULT_MODEL)
    end

    it 'uses explicit model parameter over configuration' do
      Boxcars.configuration.default_model = 'gpt-4o'

      allow(Boxcars::Anthropic).to receive(:new)
      Boxcars::Engines.engine(model: 'sonnet')
      expect(Boxcars::Anthropic).to have_received(:new).with(model: 'claude-sonnet-4-0')
    end
  end
end
