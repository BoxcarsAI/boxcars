# frozen_string_literal: true

require 'spec_helper'
require 'boxcars/engine/gemini_ai'
require 'boxcars/observability'
require 'boxcars/prompt'
require 'openai' # Gemini engine uses the OpenAI gem

RSpec.describe Boxcars::GeminiAi do
  subject(:engine) { described_class.new(**engine_params) }

  let(:prompt_template) { "What is the capital of %<country>s?" } # Changed {{country}} to %{country}
  let(:prompt) { Boxcars::Prompt.new(template: prompt_template) }
  let(:inputs) { { country: "France" } }
  let(:api_key_param) { "test_gemini_api_key" }
  let(:engine_params) { {} }

  let(:mock_gemini_client) { instance_double(OpenAI::Client) }
  # Using OpenAI-like chat response structure as the gemini_client uses OpenAI::Client
  let(:gemini_chat_success_response_openai_style) do
    {
      "id" => "gemini-chat-123",
      "object" => "chat.completion", # This might differ for actual Gemini via OpenAI client
      "created" => Time.now.to_i,
      "model" => "gemini-1.5-flash-latest",
      "choices" => [{
        "index" => 0,
        "message" => { "role" => "assistant", "content" => "Paris" }, # 'assistant' role for OpenAI client
        "finish_reason" => "stop"
      }],
      "usage" => { "prompt_tokens" => 10, "completion_tokens" => 1, "total_tokens" => 11 }
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
    Boxcars::Observability.backend = dummy_observability_backend
    allow(Boxcars.configuration).to receive(:gemini_api_key).and_return(api_key_param)
    # Mock the self.gemini_client method to return our mock_gemini_client
    allow(described_class).to receive(:gemini_client).with(gemini_api_key: api_key_param).and_return(mock_gemini_client)
    # Also mock if called without explicit key (to use config)
    allow(described_class).to receive(:gemini_client).with(gemini_api_key: nil).and_return(mock_gemini_client)
  end

  describe 'observability integration with OpenAI client for Gemini' do
    context 'when API call is successful (OpenAI-style response)' do
      before do
        allow(mock_gemini_client).to receive(:chat).and_return(gemini_chat_success_response_openai_style)
      end

      it 'tracks an llm_call event with correct properties' do
        engine.client(prompt: prompt, inputs: inputs, temperature: 0.5)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        expect(tracked_event[:event]).to eq('llm_call')

        props = tracked_event[:properties]
        expect(props[:provider]).to eq(:gemini_ai)
        expect(props[:model_name]).to eq("gemini-1.5-flash-latest")
        expect(props[:success]).to be true
        expect(props[:duration_ms]).to be_a(Integer).and be >= 0
        expect(props[:inputs]).to eq(inputs)
        expect(props[:api_call_parameters]).to include(model: "gemini-1.5-flash-latest", temperature: 0.5)
        expect(props[:prompt_content]).to be_an(Array)
        expect(props[:prompt_content].first[:role].to_s).to eq("user")
        expect(props[:prompt_content].first[:content]).to include("What is the capital of France?")
        expect(props[:response_parsed_body]).to eq(gemini_chat_success_response_openai_style)
        expect(props[:response_raw_body]).to eq(JSON.pretty_generate(gemini_chat_success_response_openai_style))
        expect(props[:status_code]).to eq(200) # Inferred
        expect(props).not_to have_key(:error_message)
      end
    end

    context 'when API call is successful (Native Gemini-style response)' do
      before do
        allow(mock_gemini_client).to receive(:chat).and_return(gemini_native_success_response)
      end

      it 'tracks an llm_call event and handles native response structure' do
        engine.client(prompt: prompt, inputs: inputs) # Assuming client can parse this

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        props = tracked_event[:properties]

        expect(props[:provider]).to eq(:gemini_ai)
        expect(props[:success]).to be true
        expect(props[:response_parsed_body]).to eq(gemini_native_success_response)
        # The run method should correctly extract "Paris"
        expect(engine.run("What is the capital of France?")).to eq("Paris")
      end
    end

    context 'when API key is missing (ConfigurationError)' do
      before do
        # Make gemini_client raise the error when api key is effectively nil
        allow(Boxcars.configuration).to receive(:gemini_api_key).with(gemini_api_key: nil).and_raise(Boxcars::ConfigurationError.new("Gemini API key not set"))
        # Redefine the mock for self.gemini_client to reflect this
        allow(described_class).to receive(:gemini_client).with(gemini_api_key: nil).and_call_original
      end

      it 'tracks an llm_call event with failure details' do
        expect do
          engine.client(prompt: prompt, inputs: inputs) # No explicit key, relies on config
        end.to raise_error(Boxcars::ConfigurationError, /Gemini API key not set/)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        props = dummy_observability_backend.tracked_events.first[:properties]
        expect(props[:success]).to be false
        expect(props[:error_message]).to match(/Gemini API key not set/)
        expect(props[:error_class]).to eq("Boxcars::ConfigurationError")
      end
    end

    context 'when OpenAI::Error is raised by the client' do
      let(:openai_error) { OpenAI::Error.new("Gemini service error via OpenAI client.").tap { |e| allow(e).to receive(:http_status).and_return(500) } }

      before do
        allow(mock_gemini_client).to receive(:chat).and_raise(openai_error)
      end

      it 'tracks an llm_call event with error details' do
        expect do
          engine.client(prompt: prompt, inputs: inputs)
        end.to raise_error(OpenAI::Error, "Gemini service error via OpenAI client.")

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        props = dummy_observability_backend.tracked_events.first[:properties]
        expect(props[:success]).to be false
        expect(props[:error_message]).to eq("Gemini service error via OpenAI client.")
        expect(props[:error_class]).to eq("OpenAI::Error")
        expect(props[:status_code]).to eq(500)
        expect(props[:provider]).to eq(:gemini_ai)
      end
    end

    describe '#run method' do
      it 'calls client and processes its output' do
        allow(mock_gemini_client).to receive(:chat).and_return(gemini_chat_success_response_openai_style)
        result = engine.run("test question for gemini")
        expect(result).to eq("Paris") # Based on the mocked response content

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        expect(dummy_observability_backend.tracked_events.first[:event]).to eq('llm_call')
      end
    end
  end
end
