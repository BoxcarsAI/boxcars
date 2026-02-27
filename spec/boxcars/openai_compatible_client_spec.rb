# frozen_string_literal: true

require "spec_helper"

RSpec.describe Boxcars::OpenAICompatibleClient do
  around do |example|
    original_backend = Boxcars.configuration.openai_client_backend
    original_require_native = Boxcars.configuration.openai_official_require_native
    original_builder = described_class.official_client_builder
    original_config_builder = Boxcars.configuration.openai_official_client_builder
    original_bridge_warning_state = described_class.instance_variable_get(:@compatibility_bridge_warning_emitted)
    example.run
    Boxcars.configuration.openai_client_backend = original_backend
    Boxcars.configuration.openai_official_require_native = original_require_native
    described_class.official_client_builder = original_builder
    Boxcars.configuration.openai_official_client_builder = original_config_builder
    described_class.instance_variable_set(:@compatibility_bridge_warning_emitted, original_bridge_warning_state)
  end

  describe ".build" do
    it "builds an OpenAI::Client with only provided options" do
      client = instance_double(OpenAI::Client)

      expect(OpenAI::Client).to receive(:new).with(
        access_token: "abc",
        uri_base: "https://api.groq.com/openai/v1"
      ).and_return(client)

      expect(described_class.build(access_token: "abc", uri_base: "https://api.groq.com/openai/v1", backend: :ruby_openai)).to eq(client)
    end

    it "passes organization_id and log_errors when present" do
      client = instance_double(OpenAI::Client)

      expect(OpenAI::Client).to receive(:new).with(
        access_token: "abc",
        organization_id: "org_123",
        log_errors: true
      ).and_return(client)

      described_class.build(access_token: "abc", organization_id: "org_123", log_errors: true, backend: :ruby_openai)
    end

    it "uses the configured backend when no backend is passed" do
      client = instance_double(OpenAI::Client)
      Boxcars.configuration.openai_client_backend = "ruby_openai"

      expect(OpenAI::Client).to receive(:new).with(access_token: "abc").and_return(client)

      expect(described_class.build(access_token: "abc")).to eq(client)
    end

    it "raises when ruby_openai backend is selected but an official-style OpenAI::Client is loaded" do
      fake_official_client_class = Class.new do
        def initialize(api_key:) = api_key
        def self.name = "OpenAI::Client"
      end
      stub_const("OpenAI::Client", fake_official_client_class)

      expect do
        described_class.build(access_token: "abc", backend: :ruby_openai)
      end.to raise_error(Boxcars::ConfigurationError, /requires ruby-openai's OpenAI::Client/)
    end

    it "lets an explicit backend override the configured backend" do
      client = instance_double(OpenAI::Client)
      Boxcars.configuration.openai_client_backend = :official_openai

      expect(OpenAI::Client).to receive(:new).with(access_token: "abc").and_return(client)

      expect(described_class.build(access_token: "abc", backend: :ruby_openai)).to eq(client)
    end

    it "raises for an unsupported backend" do
      expect do
        described_class.build(access_token: "abc", backend: :mystery_sdk)
      end.to raise_error(
        Boxcars::ConfigurationError,
        /Unsupported openai_client_backend: :mystery_sdk/
      )
    end

    it "auto-configures a compatibility builder for official_openai when ruby-openai client class is loaded" do
      described_class.official_client_builder = nil
      Boxcars.configuration.openai_official_client_builder = nil

      built = described_class.build(access_token: "abc", backend: :official_openai)
      expect(built).to be_a(OpenAI::Client)
    end

    it "emits a one-time warning when official backend uses the ruby-openai compatibility bridge" do
      described_class.official_client_builder = nil
      Boxcars.configuration.openai_official_client_builder = nil
      described_class.instance_variable_set(:@compatibility_bridge_warning_emitted, false)

      logger = instance_double(Logger)
      allow(Boxcars).to receive(:logger).and_return(logger)
      expect(logger).to receive(:warn).once.with(/ruby-openai compatibility bridge/)

      2.times { described_class.build(access_token: "abc", backend: :official_openai) }
    end

    it "raises in native-only mode when official backend would otherwise use ruby-openai bridge" do
      described_class.official_client_builder = nil
      Boxcars.configuration.openai_official_client_builder = nil
      Boxcars.configuration.openai_official_require_native = true
      allow(described_class).to receive(:detect_official_client_class).and_return(nil)

      expect do
        described_class.build(access_token: "abc", backend: :official_openai)
      end.to raise_error(Boxcars::ConfigurationError, /requires an official client builder or a compatible OpenAI::Client class/)
    end

    it "does not classify ruby-openai client class as official" do
      described_class.official_client_builder = nil
      expect(described_class.send(:detect_official_client_class)).to be_nil
    end

    it "configures a compatibility builder from ruby-openai client class" do
      described_class.official_client_builder = nil
      expect(described_class.configure_official_client_builder!).to be(true)
      expect(described_class.official_client_builder).to respond_to(:call)
    end

    it "uses the configured official client builder for official_openai" do
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
          log_errors: true,
          backend: :official_openai
        )
      ).to eq(official_client)
    end

    it "uses configuration openai_official_client_builder when module builder is not set" do
      official_client = double("OfficialOpenAIClientFromConfig") # rubocop:disable RSpec/VerifiedDoubles
      described_class.official_client_builder = nil
      Boxcars.configuration.openai_official_client_builder = lambda do |access_token:, uri_base:, organization_id:, log_errors:|
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
          log_errors: true,
          backend: :official_openai
        )
      ).to eq(official_client)
    end

    it "prefers module-level builder over configuration builder" do
      module_client = double("ModuleBuilderClient") # rubocop:disable RSpec/VerifiedDoubles
      Boxcars.configuration.openai_official_client_builder = ->(**) { raise "should not be called" }
      described_class.official_client_builder = ->(**) { module_client }

      expect(
        described_class.build(
          access_token: "abc",
          backend: :official_openai
        )
      ).to eq(module_client)
    end

    it "uses the latest configuration builder when module-level builder is unset" do
      first_client = double("FirstConfigClient") # rubocop:disable RSpec/VerifiedDoubles
      second_client = double("SecondConfigClient") # rubocop:disable RSpec/VerifiedDoubles

      described_class.official_client_builder = nil
      Boxcars.configuration.openai_official_client_builder = ->(**) { first_client }
      expect(described_class.build(access_token: "abc", backend: :official_openai)).to eq(first_client)

      Boxcars.configuration.openai_official_client_builder = ->(**) { second_client }
      expect(described_class.build(access_token: "abc", backend: :official_openai)).to eq(second_client)
    end

    it "auto-detects an official-style OpenAI::Client and builds it without an explicit builder" do
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
        log_errors: true,
        backend: :official_openai
      )

      expect(built).to be_a(fake_official_client_class)
      expect(built.kwargs).to include(api_key: "abc")
    end
  end

  describe ".validate_backend_configuration!" do
    it "returns true for ruby_openai backend" do
      expect(described_class.validate_backend_configuration!(backend: :ruby_openai)).to eq(true)
    end

    it "raises for ruby_openai backend when loaded OpenAI::Client is not ruby-openai compatible" do
      fake_official_client_class = Class.new do
        def initialize(api_key:) = api_key
        def self.name = "OpenAI::Client"
      end
      stub_const("OpenAI::Client", fake_official_client_class)

      expect do
        described_class.validate_backend_configuration!(backend: :ruby_openai)
      end.to raise_error(Boxcars::ConfigurationError, /requires ruby-openai's OpenAI::Client/)
    end

    it "returns true for official backend when configuration builder is present" do
      Boxcars.configuration.openai_official_client_builder = ->(**) { double("OfficialClient") } # rubocop:disable RSpec/VerifiedDoubles
      described_class.official_client_builder = nil

      expect(described_class.validate_backend_configuration!(backend: :official_openai)).to eq(true)
    end

    it "raises for official backend when no builder or official class is available" do
      Boxcars.configuration.openai_official_client_builder = nil
      described_class.official_client_builder = nil
      allow(described_class).to receive(:detect_official_client_class).and_return(nil)
      allow(described_class).to receive(:detect_ruby_openai_client_class).and_return(nil)

      expect do
        described_class.validate_backend_configuration!(backend: :official_openai)
      end.to raise_error(Boxcars::ConfigurationError, /no compatible OpenAI::Client was detected/)
    end

    it "raises for official backend in native-only mode when official client is unavailable" do
      Boxcars.configuration.openai_official_require_native = true
      Boxcars.configuration.openai_official_client_builder = nil
      described_class.official_client_builder = nil
      allow(described_class).to receive(:detect_official_client_class).and_return(nil)

      expect do
        described_class.validate_backend_configuration!(backend: :official_openai)
      end.to raise_error(Boxcars::ConfigurationError, /native-only mode/)
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
