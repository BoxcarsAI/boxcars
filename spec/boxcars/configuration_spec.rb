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

  describe '#openai_client_backend' do
    it 'defaults to :official_openai when env is not set' do
      allow(ENV).to receive(:fetch).with("OPENAI_CLIENT_BACKEND", "official_openai").and_return("official_openai")
      cfg = described_class.new

      expect(cfg.openai_client_backend).to eq(:official_openai)
    end

    it 'uses OPENAI_CLIENT_BACKEND when provided' do
      allow(ENV).to receive(:fetch).with("OPENAI_CLIENT_BACKEND", "official_openai").and_return("ruby_openai")
      cfg = described_class.new

      expect(cfg.openai_client_backend).to eq(:ruby_openai)
    end

    it 'falls back to :official_openai when OPENAI_CLIENT_BACKEND is empty' do
      allow(ENV).to receive(:fetch).with("OPENAI_CLIENT_BACKEND", "official_openai").and_return("")
      cfg = described_class.new

      expect(cfg.openai_client_backend).to eq(:official_openai)
    end

    it 'raises on invalid OPENAI_CLIENT_BACKEND values' do
      allow(ENV).to receive(:fetch).with("OPENAI_CLIENT_BACKEND", "official_openai").and_return("unsupported_backend")

      expect do
        described_class.new
      end.to raise_error(Boxcars::ConfigurationError, /Unsupported openai_client_backend/)
    end

    it 'raises on invalid backend assignment' do
      expect do
        configuration.openai_client_backend = :invalid_backend
      end.to raise_error(Boxcars::ConfigurationError, /Unsupported openai_client_backend/)
    end
  end

  describe '#openai_official_client_builder' do
    it 'accepts nil' do
      configuration.openai_official_client_builder = nil
      expect(configuration.openai_official_client_builder).to be_nil
    end

    it 'accepts a callable object' do
      builder = ->(**) {}
      configuration.openai_official_client_builder = builder
      expect(configuration.openai_official_client_builder).to eq(builder)
    end

    it 'rejects non-callable values' do
      expect do
        configuration.openai_official_client_builder = "not-callable"
      end.to raise_error(Boxcars::ConfigurationError, /must be callable/)
    end
  end

  describe '#openai_official_require_native' do
    it 'defaults to false when env is not set' do
      allow(ENV).to receive(:fetch).with("OPENAI_OFFICIAL_REQUIRE_NATIVE", false).and_return(false)
      cfg = described_class.new

      expect(cfg.openai_official_require_native).to be(false)
    end

    it 'uses OPENAI_OFFICIAL_REQUIRE_NATIVE when provided' do
      allow(ENV).to receive(:fetch).with("OPENAI_OFFICIAL_REQUIRE_NATIVE", false).and_return("true")
      cfg = described_class.new

      expect(cfg.openai_official_require_native).to be(true)
    end

    it 'accepts boolean-like assignment values' do
      configuration.openai_official_require_native = "yes"
      expect(configuration.openai_official_require_native).to be(true)

      configuration.openai_official_require_native = "0"
      expect(configuration.openai_official_require_native).to be(false)
    end

    it 'raises on invalid assignment values' do
      expect do
        configuration.openai_official_require_native = "maybe"
      end.to raise_error(Boxcars::ConfigurationError, /must be a boolean-like value/)
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
