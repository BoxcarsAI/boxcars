# frozen_string_literal: true

require 'spec_helper'
require 'boxcars/engine/intelligence_base'
require 'boxcars/observability'
require 'boxcars/prompt'

# Stub Intelligence::ChatResponse to allow instance_double to work
module Intelligence
  class ChatResponse
    def success?
    end

    def body
    end

    def status
    end

    def reason_phrase
    end
  end
end

# A minimal concrete class for testing IntelligenceBase
class TestableIntelligenceEngine < Boxcars::IntelligenceBase
  def initialize(**kwargs)
    super(provider: :test_provider, name: "TestEngine", description: "Test Engine Desc", **kwargs)
  end

  def lookup_provider_api_key(*)
    # Rails.logger.debug "Looking up API key for params: #{params}"
    "test_api_key_from_lookup"
  end

  # Override default_model_params if needed for tests
  def default_model_params
    { model: "test-default-model" }
  end
end

RSpec.describe Boxcars::IntelligenceBase do # rubocop:disable RSpec/SpecFilePathFormat
  subject(:engine) { TestableIntelligenceEngine.new(**engine_params) }

  let(:prompt_template) { "Translate this: {{text}}" }
  # Helper to define the mock for request.chat
  let(:mock_request_chat_call) do
    allow(mock_intelligence_request).to receive(:chat).and_return(mock_chat_response)
  end
  let(:prompt) { Boxcars::Prompt.new(template: prompt_template) }
  let(:inputs) { { text: "hello world" } }
  let(:api_key_param) { "override_api_key" }

  let(:mock_intelligence_adapter_class) { class_double(Intelligence::Adapter::Base).as_stubbed_const }
  let(:mock_intelligence_adapter) { instance_double(Intelligence::Adapter::Base) }
  let(:mock_intelligence_request) { instance_double(Intelligence::ChatRequest) }
  let(:mock_chat_response) do
    instance_double(Intelligence::ChatResponse,
                    success?: true,
                    body: { choices: [{ message: { content: "hola mundo" } }] }.to_json,
                    status: 200,
                    reason_phrase: "OK")
  end

  let(:engine_params) { {} } # Default, can be overridden in contexts

  before do
    # Reset observability backend
    Boxcars::Observability.backend = nil

    # Mock the Intelligence gem interactions
    allow(Intelligence::Adapter).to receive(:[]).with(:test_provider).and_return(mock_intelligence_adapter_class)
    # Expect only a string (api_key)
    allow(mock_intelligence_adapter_class).to receive(:new).with(an_instance_of(String)).and_return(mock_intelligence_adapter)
    allow(Intelligence::ChatRequest).to receive(:new).with(adapter: mock_intelligence_adapter).and_return(mock_intelligence_request)

    allow(mock_request_chat_call) # Define the default mock for chat
  end

  describe 'observability integration in #client' do
    let(:dummy_observability_backend) do
      Class.new do
        include Boxcars::ObservabilityBackend
        attr_reader :tracked_events

        def initialize
          @tracked_events = []
        end

        def track(event:, properties:)
          @tracked_events << { event: event, properties: properties }
        end
      end.new
    end

    before do
      Boxcars::Observability.backend = dummy_observability_backend
    end

    context 'when API call is successful' do
      it 'tracks a $ai_generation event with correct PostHog properties' do
        engine.client(prompt: prompt, inputs: inputs, api_key: api_key_param, temperature: 0.7)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        expect(tracked_event[:event]).to eq('$ai_generation')

        props = tracked_event[:properties]
        expect(props[:$ai_provider]).to eq("test_provider")
        expect(props[:$ai_model]).to eq("test-default-model") # from default_model_params
        expect(props[:$ai_is_error]).to be false
        expect(props[:$ai_latency]).to be_a(Float).and be >= 0
        expect(props[:$ai_http_status]).to eq(200)
        expect(props[:$ai_base_url]).to eq("https://api.test_provider.com/v1")
        expect(props[:$ai_trace_id]).to be_a(String)

        # Check input format
        ai_input = JSON.parse(props[:$ai_input])
        expect(ai_input).to be_an(Array)

        # Check output format
        ai_output = JSON.parse(props[:$ai_output_choices])
        expect(ai_output).to be_an(Array)
        expect(ai_output.first).to include("role" => "assistant", "content" => "hola mundo")

        expect(props).not_to have_key(:$ai_error)
      end

      context 'when engine has specific model params' do
        let(:engine_params) { { model: "engine-specific-model" } }

        it 'uses engine model params if not overridden in call' do
          engine.client(prompt: prompt, inputs: inputs) # No model in call
          props = dummy_observability_backend.tracked_events.first[:properties]
          expect(props[:$ai_model]).to eq("engine-specific-model")
        end

        it 'uses call-specific model params if provided' do
          engine.client(prompt: prompt, inputs: inputs, model: "call-specific-model")
          props = dummy_observability_backend.tracked_events.first[:properties]
          expect(props[:$ai_model]).to eq("call-specific-model")
        end
      end
    end

    context 'when API key is missing' do
      # Redefine lookup to simulate missing key
      before do
        allow(engine).to receive(:lookup_provider_api_key).and_return(nil) # rubocop:disable RSpec/SubjectStub
      end

      it 'tracks a $ai_generation event with failure details' do
        expect do
          engine.client(prompt: prompt, inputs: inputs) # No api_key passed directly
        end.to raise_error(Boxcars::Error, /No API key found/)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        props = tracked_event[:properties]

        expect(props[:$ai_is_error]).to be true
        expect(props[:$ai_error]).to match(/No API key found/)
        expect(props[:$ai_provider]).to eq("test_provider")
        expect(props[:$ai_http_status]).to eq(500) # Default for errors
      end
    end

    context 'when API call fails (e.g., network error or API error status)' do
      before do
        # Simulate Intelligence gem raising an error
        allow(mock_intelligence_request).to receive(:chat).and_raise(StandardError.new("Network timeout"))
      end

      it 'tracks a $ai_generation event with error details from raised exception' do
        expect do
          engine.client(prompt: prompt, inputs: inputs, api_key: api_key_param)
        end.to raise_error(StandardError, "Network timeout")

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        props = tracked_event[:properties]

        expect(props[:$ai_is_error]).to be true
        expect(props[:$ai_error]).to eq("Network timeout")
        expect(props[:$ai_provider]).to eq("test_provider")
        expect(props[:$ai_http_status]).to eq(500) # Default for errors
      end
    end

    context 'when API returns a non-successful status' do
      before do
        allow(mock_chat_response).to receive_messages(success?: false, status: 401, reason_phrase: "Unauthorized", body: { error: "Invalid API key" }.to_json)
        # Redefine mock_request_chat_call for this context
        allow(mock_intelligence_request).to receive(:chat).and_return(mock_chat_response)
      end

      it 'tracks a $ai_generation event with failure details from response object' do
        expect do
          engine.client(prompt: prompt, inputs: inputs, api_key: api_key_param)
        end.to raise_error(Boxcars::Error, /Unauthorized/) # Or whatever IntelligenceBase raises

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        props = tracked_event[:properties]

        expect(props[:$ai_is_error]).to be true
        expect(props[:$ai_http_status]).to eq(401)
        expect(props[:$ai_error]).to eq("Unauthorized")
        expect(props[:$ai_provider]).to eq("test_provider")
      end
    end
  end
end
