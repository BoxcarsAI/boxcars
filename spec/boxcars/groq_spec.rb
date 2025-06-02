# frozen_string_literal: true

require 'spec_helper'
require 'boxcars/engine/groq'
require 'boxcars/observability'
require 'boxcars/prompt'
require 'openai' # Groq engine uses the OpenAI gem

RSpec.describe Boxcars::Groq do
  subject(:engine) { described_class.new(**engine_params) }

  let(:prompt_template) { "What is Groq and what makes it fast for %<task>s?" }
  let(:prompt) { Boxcars::Prompt.new(template: prompt_template) }
  let(:inputs) { { task: "inference" } }
  let(:api_key_param) { "test_groq_api_key" }
  let(:engine_params) { {} }

  let(:mock_groq_client) { instance_double(OpenAI::Client) }
  let(:groq_chat_success_response) do
    {
      "id" => "groq-chat-789",
      "object" => "chat.completion",
      "created" => Time.now.to_i,
      "model" => "llama3-70b-8192", # Default Groq model
      "choices" => [{
        "index" => 0,
        "message" => { "role" => "assistant", "content" => "Groq is known for its LPU Inference Engine..." },
        "finish_reason" => "stop"
      }],
      "usage" => { "prompt_tokens" => 15, "completion_tokens" => 50, "total_tokens" => 65 }
      # "x_groq" => { "id" => "req_someid" } # Example of extra field Groq might return
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
    allow(Boxcars.configuration).to receive(:groq_api_key).and_return(api_key_param)
    allow(described_class).to receive(:groq_client).with(groq_api_key: api_key_param).and_return(mock_groq_client)
    allow(described_class).to receive(:groq_client).with(groq_api_key: nil).and_return(mock_groq_client)
  end

  describe 'observability integration with OpenAI client for Groq' do
    context 'when API call is successful' do
      before do
        allow(mock_groq_client).to receive(:chat).and_return(groq_chat_success_response)
      end

      it 'tracks an $ai_generation event with correct properties' do
        engine.client(prompt: prompt, inputs: inputs, temperature: 0.6)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        expect(tracked_event[:event]).to eq('$ai_generation')

        props = tracked_event[:properties]
        expect(props[:$ai_provider]).to eq('groq')
        expect(props[:$ai_model]).to eq("llama3-70b-8192")
        expect(props[:$ai_is_error]).to be false
        expect(props[:$ai_latency]).to be_a(Float).and be >= 0
        expect(props[:$ai_http_status]).to eq(200)
        expect(props[:$ai_base_url]).to eq('https://api.groq.com/openai/v1')

        # Check input format
        ai_input = JSON.parse(props[:$ai_input])
        expect(ai_input).to be_an(Array)
        expect(ai_input.first['role']).to eq('user')
        expect(ai_input.first['content']).to include('What is Groq and what makes it fast for inference?')

        # Check output format
        ai_output = JSON.parse(props[:$ai_output_choices])
        expect(ai_output).to be_an(Array)
        expect(ai_output.first['role']).to eq('assistant')
        expect(ai_output.first['content']).to eq('Groq is known for its LPU Inference Engine...')

        # Check token counts
        expect(props[:$ai_input_tokens]).to eq(15)
        expect(props[:$ai_output_tokens]).to eq(50)

        expect(props).not_to have_key(:$ai_error)
      end
    end

    context 'when API key is missing (ConfigurationError)' do
      before do
        allow(Boxcars.configuration).to receive(:groq_api_key).with(groq_api_key: nil).and_raise(Boxcars::ConfigurationError.new("Groq API key not set"))
        allow(described_class).to receive(:groq_client).with(groq_api_key: nil).and_call_original
      end

      it 'tracks an $ai_generation event with failure details' do
        expect do
          engine.client(prompt: prompt, inputs: inputs)
        end.to raise_error(Boxcars::ConfigurationError, /Groq API key not set/)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        expect(tracked_event[:event]).to eq('$ai_generation')

        props = tracked_event[:properties]
        expect(props[:$ai_is_error]).to be true
        expect(props[:$ai_error]).to match(/Groq API key not set/)
        expect(props[:$ai_provider]).to eq('groq')
        expect(props[:$ai_http_status]).to eq(500)
      end
    end

    context 'when OpenAI::Error is raised by the client (e.g. Groq server error)' do
      let(:openai_error) { OpenAI::Error.new("Groq service unavailable").tap { |e| allow(e).to receive(:http_status).and_return(503) } }

      before do
        allow(mock_groq_client).to receive(:chat).and_raise(openai_error)
      end

      it 'tracks an $ai_generation event with error details' do
        expect do
          engine.client(prompt: prompt, inputs: inputs)
        end.to raise_error(OpenAI::Error, "Groq service unavailable")

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        expect(tracked_event[:event]).to eq('$ai_generation')

        props = tracked_event[:properties]
        expect(props[:$ai_is_error]).to be true
        expect(props[:$ai_error]).to eq("Groq service unavailable")
        expect(props[:$ai_provider]).to eq('groq')
        expect(props[:$ai_http_status]).to eq(503)
      end
    end

    describe '#run method' do
      it 'calls client and processes its output' do
        allow(mock_groq_client).to receive(:chat).and_return(groq_chat_success_response)
        result = engine.run("test question for groq")
        expect(result).to eq("Groq is known for its LPU Inference Engine...")

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        expect(dummy_observability_backend.tracked_events.first[:event]).to eq('$ai_generation')
      end
    end
  end
end
