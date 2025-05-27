# frozen_string_literal: true

require 'spec_helper'
require 'boxcars/engine/ollama'
require 'boxcars/observability'
require 'boxcars/prompt'
require 'openai' # Ollama engine uses the OpenAI gem

RSpec.describe Boxcars::Ollama do
  subject(:engine) { described_class.new(**engine_params) }

  let(:prompt_template) { "Explain %<concept>s in simple terms." }
  let(:prompt) { Boxcars::Prompt.new(template: prompt_template) }
  let(:inputs) { { concept: "quantum physics" } }
  let(:engine_params) { {} } # Default engine params

  let(:mock_ollama_client) { instance_double(OpenAI::Client) }
  let(:ollama_chat_success_response) do
    {
      "id" => "ollama-chat-456", # Example ID
      "object" => "chat.completion", # Assuming OpenAI-compatible response
      "created" => Time.now.to_i,
      "model" => "llama3", # Default Ollama model from engine
      "choices" => [{
        "index" => 0,
        "message" => { "role" => "assistant", "content" => "Quantum physics is about tiny things acting weird." },
        "finish_reason" => "stop"
      }],
      "usage" => { "prompt_tokens" => 10, "completion_tokens" => 8, "total_tokens" => 18 } # Example usage
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
    # Mock the self.ollama_client method to return our mock_ollama_client
    # No API key needed for Ollama usually, so no Boxcars.configuration mock for api_key.
    allow(described_class).to receive(:ollama_client).and_return(mock_ollama_client)
  end

  describe 'observability integration with OpenAI client for Ollama' do
    context 'when API call is successful' do
      before do
        allow(mock_ollama_client).to receive(:chat).and_return(ollama_chat_success_response)
      end

      it 'tracks an llm_call event with correct properties' do
        engine.client(prompt: prompt, inputs: inputs, temperature: 0.6)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        expect(tracked_event[:event]).to eq('llm_call')

        props = tracked_event[:properties]
        expect(props[:provider]).to eq(:ollama)
        expect(props[:model_name]).to eq("llama3") # Default model
        expect(props[:success]).to be true
        expect(props[:duration_ms]).to be_a(Integer).and be >= 0
        expect(props[:inputs]).to eq(inputs)
        expect(props[:api_call_parameters]).to include(model: "llama3", temperature: 0.6)
        expect(props[:prompt_content]).to be_an(Array)
        expect(props[:prompt_content].first[:role].to_s).to eq("user")
        expect(props[:prompt_content].first[:content]).to include("Explain quantum physics in simple terms.")
        expect(props[:response_parsed_body]).to eq(ollama_chat_success_response)
        expect(props[:response_raw_body]).to eq(JSON.pretty_generate(ollama_chat_success_response))
        expect(props[:status_code]).to eq(200) # Inferred for local success
        expect(props).not_to have_key(:error_message)
      end
    end

    context 'when Ollama service is unavailable (OpenAI::Error)' do
      let(:connection_error) { OpenAI::Error.new("Connection refused - connect(2) for \"localhost\" port 11434") }

      before do
        # Simulate the OpenAI client failing to connect
        allow(mock_ollama_client).to receive(:chat).and_raise(connection_error)
        # If http_status is available on the error, mock it
        allow(connection_error).to receive(:http_status).and_return(nil) # Or a specific code if applicable
      end

      it 'tracks an llm_call event with connection error details' do
        expect do
          engine.client(prompt: prompt, inputs: inputs)
        end.to raise_error(OpenAI::Error, /Connection refused/)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        props = dummy_observability_backend.tracked_events.first[:properties]
        expect(props[:success]).to be false
        expect(props[:error_message]).to match(/Connection refused/)
        expect(props[:error_class]).to eq("OpenAI::Error")
        # status_code might be nil if the error doesn't provide it before HTTP exchange
        expect(props[:provider]).to eq(:ollama)
      end
    end

    context 'when Ollama returns an error in the response body' do
      let(:ollama_error_response) do
        { "error" => "model 'unknown_model' not found, try pulling it first" }
      end

      before do
        allow(mock_ollama_client).to receive(:chat).and_return(ollama_error_response)
      end

      it 'tracks an llm_call event with error details from response' do
        expect do
          engine.client(prompt: prompt, inputs: inputs, model: "unknown_model")
        end.to raise_error(Boxcars::Error, /model 'unknown_model' not found/)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        props = dummy_observability_backend.tracked_events.first[:properties]
        expect(props[:success]).to be false
        expect(props[:error_message]).to eq("model 'unknown_model' not found, try pulling it first")
        expect(props[:error_class]).to eq("Boxcars::Error") # As it's wrapped in client
        expect(props[:response_parsed_body]).to eq(ollama_error_response) # The error response itself
        expect(props[:provider]).to eq(:ollama)
      end
    end

    describe '#run method' do
      it 'calls client and processes its output' do
        allow(mock_ollama_client).to receive(:chat).and_return(ollama_chat_success_response)
        result = engine.run("test question for ollama")
        expect(result).to eq("Quantum physics is about tiny things acting weird.")

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        expect(dummy_observability_backend.tracked_events.first[:event]).to eq('llm_call')
      end
    end
  end
end
