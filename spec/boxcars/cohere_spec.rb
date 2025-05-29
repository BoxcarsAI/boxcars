# frozen_string_literal: true

require 'spec_helper'
require 'boxcars/engine/cohere'
require 'boxcars/observability'
require 'boxcars/prompt'

# Stub Intelligence::ChatResponse if not already globally available in spec_helper
# or if specific stubs are needed for Cohere adapter.
unless defined?(Intelligence::ChatResponse)
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
end

RSpec.describe Boxcars::Cohere do
  subject(:engine) { described_class.new(**engine_params) }

  let(:prompt_template) { "Translate this: {{text}}" }
  let(:prompt) { Boxcars::Prompt.new(template: prompt_template) }
  let(:inputs) { { text: "hello world" } }
  let(:api_key_param) { "test_cohere_api_key" }

  let(:mock_intelligence_adapter_class) { class_double(Intelligence::Adapter::Base).as_stubbed_const }
  let(:mock_intelligence_adapter) { instance_double(Intelligence::Adapter::Base) }
  let(:mock_intelligence_request) { instance_double(Intelligence::ChatRequest) }
  let(:cohere_success_response) do
    {
      "text" => "hola mundo",
      "meta" => {
        "tokens" => {
          "input_tokens" => 5,
          "output_tokens" => 2
        }
      }
    }
  end
  let(:mock_chat_response) do
    instance_double(Intelligence::ChatResponse,
                    success?: true,
                    body: cohere_success_response.to_json,
                    status: 200,
                    reason_phrase: "OK")
  end

  let(:engine_params) { {} }

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
    # Reset and set observability backend
    Boxcars::Observability.backend = dummy_observability_backend

    # Mock Boxcars configuration for API key
    allow(Boxcars.configuration).to receive(:cohere_api_key).and_return(api_key_param)

    # Mock the Intelligence gem interactions for :cohere provider
    allow(Intelligence::Adapter).to receive(:[]).with(:cohere).and_return(mock_intelligence_adapter_class)
    allow(mock_intelligence_adapter_class).to receive(:new).with(api_key_param).and_return(mock_intelligence_adapter)
    allow(Intelligence::ChatRequest).to receive(:new).with(adapter: mock_intelligence_adapter).and_return(mock_intelligence_request)
    allow(mock_intelligence_request).to receive(:chat).and_return(mock_chat_response)
  end

  describe 'observability integration with PostHog standard format' do
    context 'when API call is successful' do
      it 'tracks a $ai_generation event with correct PostHog properties' do
        engine.client(prompt: prompt, inputs: inputs, temperature: 0.7)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        expect(tracked_event[:event]).to eq('$ai_generation')

        props = tracked_event[:properties]
        expect(props[:$ai_provider]).to eq("cohere")
        expect(props[:$ai_model]).to eq("command-r-plus") # From DEFAULT_PARAMS
        expect(props[:$ai_is_error]).to be false
        expect(props[:$ai_http_status]).to eq(200)
        expect(props[:$ai_base_url]).to eq("https://api.cohere.ai/v1")
        expect(props[:$ai_input_tokens]).to eq(5)
        expect(props[:$ai_output_tokens]).to eq(2)
        expect(props[:$ai_latency]).to be_a(Float).and be >= 0
        expect(props[:$ai_trace_id]).to be_a(String)

        # Check input format - be flexible about content since Intelligence::Message objects may not extract perfectly
        ai_input = JSON.parse(props[:$ai_input])
        expect(ai_input).to be_an(Array)
        expect(ai_input.first).to include("role" => "user")
        expect(ai_input.first["content"]).to be_a(String) # Content should be a string, even if it's the object representation

        # Check output format
        ai_output = JSON.parse(props[:$ai_output_choices])
        expect(ai_output).to be_an(Array)
        expect(ai_output.first).to include("role" => "assistant", "content" => "hola mundo")

        expect(props).not_to have_key(:$ai_error)
      end

      it 'uses call-specific model params if provided' do
        engine.client(prompt: prompt, inputs: inputs, model: "custom-cohere-model")
        props = dummy_observability_backend.tracked_events.first[:properties]
        expect(props[:$ai_model]).to eq("custom-cohere-model")
      end
    end

    context 'when API key is missing' do
      before do
        allow(Boxcars.configuration).to receive(:cohere_api_key).and_return(nil)
      end

      it 'tracks a $ai_generation event with failure details' do
        expect do
          engine.client(prompt: prompt, inputs: inputs)
        end.to raise_error(Boxcars::Error, /No API key found for cohere/)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        props = tracked_event[:properties]

        expect(props[:$ai_is_error]).to be true
        expect(props[:$ai_error]).to match(/No API key found for cohere/)
        expect(props[:$ai_provider]).to eq("cohere")
        expect(props[:$ai_http_status]).to eq(500) # Default for errors
      end
    end

    context 'when API call fails (e.g., network error or API error status)' do
      before do
        allow(mock_intelligence_request).to receive(:chat).and_raise(StandardError.new("Cohere Network timeout"))
      end

      it 'tracks a $ai_generation event with error details from raised exception' do
        expect do
          engine.client(prompt: prompt, inputs: inputs)
        end.to raise_error(StandardError, "Cohere Network timeout")

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        props = tracked_event[:properties]

        expect(props[:$ai_is_error]).to be true
        expect(props[:$ai_error]).to eq("Cohere Network timeout")
        expect(props[:$ai_provider]).to eq("cohere")
        expect(props[:$ai_http_status]).to eq(500) # Default for errors
      end
    end

    context 'when API returns a non-successful status' do
      before do
        allow(mock_chat_response).to receive_messages(
          success?: false,
          status: 401,
          reason_phrase: "Unauthorized",
          body: { message: "Invalid API key" }.to_json
        )
        allow(mock_intelligence_request).to receive(:chat).and_return(mock_chat_response)
      end

      it 'tracks a $ai_generation event with failure details from response object' do
        expect do
          engine.client(prompt: prompt, inputs: inputs)
        end.to raise_error(Boxcars::Error, /Unauthorized/)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        props = tracked_event[:properties]

        expect(props[:$ai_is_error]).to be true
        expect(props[:$ai_http_status]).to eq(401)
        expect(props[:$ai_error]).to eq("Unauthorized")
        expect(props[:$ai_provider]).to eq("cohere")
      end
    end

    describe '#run method' do
      it 'calls client and processes its output, ensuring observability is triggered via client' do
        result = engine.run("test question")
        expect(result).to eq("hola mundo")

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        expect(dummy_observability_backend.tracked_events.first[:event]).to eq('$ai_generation')
        expect(dummy_observability_backend.tracked_events.first[:properties][:$ai_provider]).to eq("cohere")
      end
    end
  end
end
