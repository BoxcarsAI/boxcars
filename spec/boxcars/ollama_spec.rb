# frozen_string_literal: true

require 'spec_helper'
require 'boxcars/engine/ollama'
require 'boxcars/prompt'
require 'openai'

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
    Boxcars.configuration.observability_backend = dummy_observability_backend
    # Mock the self.ollama_client method to return our mock_ollama_client
    # No API key needed for Ollama usually, so no Boxcars.configuration mock for api_key.
    allow(described_class).to receive(:ollama_client).and_return(mock_ollama_client)
  end

  describe 'observability integration with OpenAI client for Ollama' do
    context 'when API call is successful' do
      before do
        allow(mock_ollama_client).to receive(:chat).and_return(ollama_chat_success_response)
      end

      it 'tracks a $ai_generation event with correct properties' do
        engine.client(prompt: prompt, inputs: inputs, temperature: 0.6)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        expect(tracked_event[:event]).to eq('$ai_generation')

        props = tracked_event[:properties]
        expect(props[:$ai_provider]).to eq('ollama')
        expect(props[:$ai_model]).to eq("llama3") # Default model
        expect(props[:$ai_is_error]).to be false
        expect(props[:$ai_latency]).to be_a(Float).and be >= 0
        expect(props[:$ai_http_status]).to eq(200) # Inferred for local success
        expect(props[:$ai_base_url]).to eq('http://localhost:11434/v1')

        # Check input format
        ai_input = JSON.parse(props[:$ai_input])
        expect(ai_input).to be_an(Array)
        expect(ai_input.first['role']).to eq('user')
        expect(ai_input.first['content']).to include('Explain quantum physics in simple terms.')

        # Check output format
        ai_output = JSON.parse(props[:$ai_output_choices])
        expect(ai_output).to be_an(Array)
        expect(ai_output.first['role']).to eq('assistant')
        expect(ai_output.first['content']).to eq('Quantum physics is about tiny things acting weird.')

        # Check token counts
        expect(props[:$ai_input_tokens]).to eq(10)
        expect(props[:$ai_output_tokens]).to eq(8)

        expect(props).not_to have_key(:$ai_error)
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

      it 'tracks a $ai_generation event with connection error details' do
        expect do
          engine.client(prompt: prompt, inputs: inputs)
        end.to raise_error(OpenAI::Error, /Connection refused/)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        expect(tracked_event[:event]).to eq('$ai_generation')

        props = tracked_event[:properties]
        expect(props[:$ai_is_error]).to be true
        expect(props[:$ai_error]).to match(/Connection refused/)
        expect(props[:$ai_provider]).to eq('ollama')
        expect(props[:$ai_http_status]).to eq(500) # Default for errors
      end
    end

    context 'when Ollama returns an error in the response body' do
      let(:ollama_error_response) do
        { "error" => "model 'unknown_model' not found, try pulling it first" }
      end

      before do
        allow(mock_ollama_client).to receive(:chat).and_return(ollama_error_response)
      end

      it 'tracks a $ai_generation event with error details from response' do
        expect do
          engine.client(prompt: prompt, inputs: inputs, model: "unknown_model")
        end.to raise_error(Boxcars::Error, /model 'unknown_model' not found/)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        expect(tracked_event[:event]).to eq('$ai_generation')

        props = tracked_event[:properties]
        expect(props[:$ai_is_error]).to be true
        expect(props[:$ai_error]).to eq("model 'unknown_model' not found, try pulling it first")
        expect(props[:$ai_provider]).to eq('ollama')
        expect(props[:$ai_http_status]).to eq(500) # Default for errors
      end
    end

    describe '#run method' do
      it 'calls client and processes its output' do
        allow(mock_ollama_client).to receive(:chat).and_return(ollama_chat_success_response)
        result = engine.run("test question for ollama")
        expect(result).to eq("Quantum physics is about tiny things acting weird.")

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        expect(dummy_observability_backend.tracked_events.first[:event]).to eq('$ai_generation')
      end
    end
  end
end
