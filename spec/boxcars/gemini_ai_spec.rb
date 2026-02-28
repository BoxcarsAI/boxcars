# frozen_string_literal: true

require 'spec_helper'
require 'boxcars/engine/gemini_ai'
require 'boxcars/prompt'
require 'openai' # Gemini engine uses the OpenAI gem

RSpec.describe Boxcars::GeminiAi do
  subject(:engine) { described_class.new(**engine_params) }

  let(:prompt_template) { "What is the capital of %<country>s?" } # Changed {{country}} to %{country}
  let(:prompt) { Boxcars::Prompt.new(template: prompt_template) }
  let(:inputs) { { country: "France" } }
  let(:api_key_param) { "test_gemini_api_key" }
  let(:engine_params) { {} }

  let(:mock_gemini_client) { double("OpenAIClient") }
  # Using OpenAI-like chat response structure as the provider_client uses OpenAI::Client
  let(:gemini_chat_success_response_openai_style) do
    {
      "id" => "gemini-chat-123",
      "object" => "chat.completion", # This might differ for actual Gemini via OpenAI client
      "created" => Time.now.to_i,
      "model" => "gemini-2.5-flash",
      "choices" => [{
        "index" => 0,
        "message" => { "role" => "assistant", "content" => "Paris" }, # 'assistant' role for OpenAI client
        "finish_reason" => "stop"
      }],
      "usage" => { "prompt_tokens" => 10, "completion_tokens" => 1, "total_tokens" => 11 }
    }
  end
  let(:gemini_chat_success_response_openai_style_symbolized) do
    {
      id: "gemini-chat-123",
      object: "chat.completion",
      created: Time.now.to_i,
      model: "gemini-2.5-flash",
      choices: [{
        index: 0,
        message: { role: "assistant", content: "Paris" },
        finish_reason: "stop"
      }],
      usage: { prompt_tokens: 10, completion_tokens: 1, total_tokens: 11 }
    }
  end
  # More native-looking Gemini response (if the OpenAI client somehow returned this)
  let(:gemini_native_success_response) do
    {
      "candidates" => [
        {
          "content" => {
            "parts" => [{ "text" => "Paris" }],
            "role" => "model" # 'model' role for Gemini native
          },
          "finishReason" => "STOP",
          "index" => 0,
          "tokenCount" => 1 # Simplified
        }
      ],
      "promptFeedback" => { "blockReason" => "OTHER" } # Example field
    }
  end

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
    Boxcars.configuration.observability_backend = dummy_observability_backend
    allow(Boxcars.configuration).to receive(:gemini_api_key).and_return(api_key_param)
    # Mock the self.provider_client method to return our mock_gemini_client
    allow(described_class).to receive(:provider_client).with(gemini_api_key: api_key_param).and_return(mock_gemini_client)
    # Also mock if called without explicit key (to use config)
    allow(described_class).to receive(:provider_client).with(gemini_api_key: nil).and_return(mock_gemini_client)
  end

  describe 'observability integration with OpenAI client for Gemini' do
    context 'when API call is successful (OpenAI-style response)' do
      before do
        allow(mock_gemini_client).to receive(:chat_create).and_return(gemini_chat_success_response_openai_style)
      end

      it 'tracks an $ai_generation event with correct properties' do
        engine.client(prompt: prompt, inputs: inputs, temperature: 0.5)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        expect(tracked_event[:event]).to eq('$ai_generation')

        props = tracked_event[:properties]
        expect(props[:$ai_provider]).to eq('gemini')
        expect(props[:$ai_model]).to eq("gemini-2.5-flash")
        expect(props[:$ai_is_error]).to be false
        expect(props[:$ai_latency]).to be_a(Float).and be >= 0
        expect(props[:$ai_http_status]).to eq(200)

        # Check input format
        ai_input = JSON.parse(props[:$ai_input])
        expect(ai_input).to be_an(Array)
        expect(ai_input.first['role']).to eq('user')
        expect(ai_input.first['content']).to include('What is the capital of France?')

        # Check output format
        ai_output = JSON.parse(props[:$ai_output_choices])
        expect(ai_output).to be_an(Array)
        expect(ai_output.first['role']).to eq('assistant')
        expect(ai_output.first['content']).to eq('Paris')

        expect(props).not_to have_key(:$ai_error)
      end

      it 'tracks an $ai_generation event from symbol-key OpenAI-style responses' do
        allow(mock_gemini_client).to receive(:chat_create).and_return(gemini_chat_success_response_openai_style_symbolized)

        engine.client(prompt: prompt, inputs: inputs, temperature: 0.5)

        props = dummy_observability_backend.tracked_events.first[:properties]
        expect(props[:$ai_provider]).to eq('gemini')
        expect(props[:$ai_input_tokens]).to eq(10)
        expect(props[:$ai_output_tokens]).to eq(1)
      end
    end

    context 'when API call is successful (Native Gemini-style response)' do
      before do
        allow(mock_gemini_client).to receive(:chat_create).and_return(gemini_native_success_response)
      end

      it 'tracks an $ai_generation event and handles native response structure' do
        engine.client(prompt: prompt, inputs: inputs) # Assuming client can parse this

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        props = tracked_event[:properties]

        expect(tracked_event[:event]).to eq('$ai_generation')
        expect(props[:$ai_provider]).to eq('gemini')
        expect(props[:$ai_is_error]).to be false

        # Check output format for native Gemini response
        ai_output = JSON.parse(props[:$ai_output_choices])
        expect(ai_output).to be_an(Array)
        expect(ai_output.first['role']).to eq('assistant')
        expect(ai_output.first['content']).to eq('Paris')

        # The run method should correctly extract "Paris"
        expect(engine.run("What is the capital of France?")).to eq("Paris")
      end
    end

    context 'when API key is missing (ConfigurationError)' do
      before do
        # Make provider_client raise the error when api key is effectively nil
        allow(Boxcars.configuration).to receive(:gemini_api_key).with(gemini_api_key: nil).and_raise(Boxcars::ConfigurationError.new("Gemini API key not set"))
        # Redefine the mock for self.provider_client to reflect this
        allow(described_class).to receive(:provider_client).with(gemini_api_key: nil).and_call_original
      end

      it 'tracks an $ai_generation event with failure details' do
        expect do
          engine.client(prompt: prompt, inputs: inputs) # No explicit key, relies on config
        end.to raise_error(Boxcars::ConfigurationError, /Gemini API key not set/)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        props = tracked_event[:properties]

        expect(tracked_event[:event]).to eq('$ai_generation')
        expect(props[:$ai_is_error]).to be true
        expect(props[:$ai_error]).to match(/Gemini API key not set/)
        expect(props[:$ai_provider]).to eq('gemini')
      end
    end

    context 'when provider error is raised by the client' do
      let(:openai_error) { StandardError.new("Gemini service error via OpenAI client.").tap { |e| allow(e).to receive(:status).and_return(500) } }

      before do
        allow(mock_gemini_client).to receive(:chat_create).and_raise(openai_error)
      end

      it 'tracks an $ai_generation event with error details' do
        expect do
          engine.client(prompt: prompt, inputs: inputs)
        end.to raise_error(StandardError, "Gemini service error via OpenAI client.")

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        props = tracked_event[:properties]

        expect(tracked_event[:event]).to eq('$ai_generation')
        expect(props[:$ai_is_error]).to be true
        expect(props[:$ai_error]).to eq("Gemini service error via OpenAI client.")
        expect(props[:$ai_http_status]).to eq(500)
        expect(props[:$ai_provider]).to eq('gemini')
      end
    end

    describe '#run method' do
      it 'calls client and processes its output' do
        allow(mock_gemini_client).to receive(:chat_create).and_return(gemini_chat_success_response_openai_style)
        result = engine.run("test question for gemini")
        expect(result).to eq("Paris") # Based on the mocked response content

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        expect(dummy_observability_backend.tracked_events.first[:event]).to eq('$ai_generation')
      end
    end
  end
end
