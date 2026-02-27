# frozen_string_literal: true

require "spec_helper"

RSpec.describe Boxcars::OpenAICompatibleClient do
  around do |example|
    original_require_native = Boxcars.configuration.openai_official_require_native
    original_builder = described_class.official_client_builder
    original_config_builder = Boxcars.configuration.openai_official_client_builder
    example.run
    Boxcars.configuration.openai_official_require_native = original_require_native
    described_class.official_client_builder = original_builder
    Boxcars.configuration.openai_official_client_builder = original_config_builder
  end

  describe ".build" do
    it "builds with the configured official client builder" do
      client = double("OfficialOpenAIClient") # rubocop:disable RSpec/VerifiedDoubles
      described_class.official_client_builder = ->(**) { client }

      expect(described_class.build(access_token: "abc")).to eq(client)
    end

    it "rejects removed backend kwarg" do
      expect do
        described_class.build(access_token: "abc", backend: :official_openai)
      end.to raise_error(ArgumentError, /unknown keyword: :backend/)
    end

    it "uses configured official client builder when present" do
      official_client = double("OfficialOpenAIClient") # rubocop:disable RSpec/VerifiedDoubles
      described_class.official_client_builder = lambda do |access_token:, uri_base:, organization_id:, log_errors:|
        expect(access_token).to eq("abc")
        expect(uri_base).to eq("https://api.openai.com/v1")
        expect(organization_id).to eq("org_123")
        expect(log_errors).to eq(true)
        official_client
      end

      expect(
        described_class.build(
          access_token: "abc",
          uri_base: "https://api.openai.com/v1",
          organization_id: "org_123",
          log_errors: true
        )
      ).to eq(official_client)
    end

    it "auto-detects official-style OpenAI::Client with api_key constructor" do
      fake_official_client_class = Class.new do
        attr_reader :kwargs

        def initialize(**kwargs)
          @kwargs = kwargs
        end

        def self.name = "OpenAI::Client"

        def chat
          Object.new
        end
      end

      stub_const("OpenAI::Client", fake_official_client_class)
      described_class.official_client_builder = nil

      built = described_class.build(
        access_token: "abc",
        uri_base: "https://api.openai.com/v1",
        organization_id: "org_123",
        log_errors: true
      )

      expect(built).to be_a(fake_official_client_class)
      expect(built.kwargs).to include(api_key: "abc")
    end
  end

  describe ".validate_client_configuration!" do
    it "returns true when an official builder is configured" do
      described_class.official_client_builder = ->(**) { double("OfficialClient") } # rubocop:disable RSpec/VerifiedDoubles
      expect(described_class.validate_client_configuration!).to eq(true)
    end

    it "returns true when configuration builder is present" do
      Boxcars.configuration.openai_official_client_builder = ->(**) { double("OfficialClient") } # rubocop:disable RSpec/VerifiedDoubles
      described_class.official_client_builder = nil

      expect(described_class.validate_client_configuration!).to eq(true)
    end

    it "raises when no builder or official class is available" do
      Boxcars.configuration.openai_official_client_builder = nil
      described_class.official_client_builder = nil
      allow(described_class).to receive(:detect_official_client_class).and_return(nil)

      expect do
        described_class.validate_client_configuration!
      end.to raise_error(Boxcars::ConfigurationError, /no compatible OpenAI::Client was detected/)
    end

    it "raises in native-only mode when official client is unavailable" do
      Boxcars.configuration.openai_official_require_native = true
      Boxcars.configuration.openai_official_client_builder = nil
      described_class.official_client_builder = nil
      allow(described_class).to receive(:detect_official_client_class).and_return(nil)

      expect do
        described_class.validate_client_configuration!
      end.to raise_error(Boxcars::ConfigurationError, /native-only mode/)
    end

    it "raises setup guidance when openai gem is missing" do
      allow(Boxcars::OptionalDependency).to receive(:require!)
        .with("openai", feature: "OpenAI and OpenAI-compatible engines")
        .and_raise(Boxcars::ConfigurationError, "Missing optional dependency 'openai'.")

      expect do
        described_class.validate_client_configuration!
      end.to raise_error(Boxcars::ConfigurationError, /optional dependency 'openai'/)
    end
  end

  describe ".official_client_builder=" do
    it "rejects non-callable values" do
      expect do
        described_class.official_client_builder = "not-callable"
      end.to raise_error(Boxcars::ConfigurationError, /must be callable/)
    end
  end
end
