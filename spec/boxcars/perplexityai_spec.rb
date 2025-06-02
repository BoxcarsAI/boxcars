# frozen_string_literal: true

require 'spec_helper'
require 'boxcars/engine/perplexityai'
require 'boxcars/observability'
require 'boxcars/prompt'
require 'faraday' # PerplexityAI engine uses Faraday

RSpec.describe Boxcars::Perplexityai do
  subject(:engine) { described_class.new(**engine_params) }

  let(:prompt_template) { "Summarize the latest news about %<topic>s." }
  let(:prompt) { Boxcars::Prompt.new(template: prompt_template) }
  let(:inputs) { { topic: "AI advancements" } }
  let(:api_key_param) { "test_perplexity_api_key" }
  let(:engine_params) { {} }

  # Mock Faraday connection and response
  let(:mock_faraday_connection) { instance_double(Faraday::Connection) }
  let(:mock_faraday_response) do
    instance_double(Faraday::Response,
                    success?: true,
                    status: 200,
                    body: {
                      "id" => "perplexity-resp-123",
                      "model" => "llama-3-sonar-large-32k-online",
                      "choices" => [{
                        "index" => 0,
                        "message" => { "role" => "assistant", "content" => "AI is advancing rapidly..." },
                        "finish_reason" => "stop"
                      }],
                      "usage" => { "prompt_tokens" => 10, "completion_tokens" => 50, "total_tokens" => 60 }
                    },
                    reason_phrase: "OK")
  end
  let(:mock_faraday_error_response) do
    instance_double(Faraday::Response,
                    success?: false,
                    status: 401,
                    body: { "error" => { "type" => "authentication_error", "message" => "Invalid API key" } },
                    reason_phrase: "Unauthorized").tap do |response|
      allow(response).to receive(:[]).with(:status).and_return(401)
      allow(response).to receive(:[]).with(:body).and_return({ "error" => { "type" => "authentication_error", "message" => "Invalid API key" } })
    end
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
    allow(Boxcars.configuration).to receive(:perplexity_api_key).and_return(api_key_param)
    allow(Faraday).to receive(:new).with(url: "https://api.perplexity.ai").and_yield(mock_faraday_connection).and_return(mock_faraday_connection)
    allow(mock_faraday_connection).to receive(:request).with(:json)
    allow(mock_faraday_connection).to receive(:response).with(:json)
    allow(mock_faraday_connection).to receive(:response).with(:raise_error)
    allow(mock_faraday_connection).to receive(:adapter).with(Faraday.default_adapter)
  end

  describe 'observability integration with direct Faraday client usage' do
    context 'when API call is successful' do
      before do
        allow(mock_faraday_connection).to receive(:post).with('/chat/completions').and_return(mock_faraday_response)
      end

      it 'tracks an $ai_generation event with correct PostHog properties' do
        engine.client(prompt: prompt, inputs: inputs, temperature: 0.3)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        expect(tracked_event[:event]).to eq('$ai_generation')

        props = tracked_event[:properties]
        expect(props[:$ai_provider]).to eq('perplexity_ai')
        expect(props[:$ai_model]).to eq("llama-3-sonar-large-32k-online")
        expect(props[:$ai_is_error]).to be false
        expect(props[:$ai_latency]).to be_a(Float).and be >= 0
        expect(props[:$ai_trace_id]).to be_a(String)
        expect(props[:$ai_base_url]).to eq('https://api.perplexity.ai')
        expect(props[:$ai_http_status]).to eq(200)

        # Check input format
        ai_input = JSON.parse(props[:$ai_input])
        expect(ai_input).to be_an(Array)
        expect(ai_input.first['role']).to eq('user')
        expect(ai_input.first['content']).to include('Summarize the latest news about AI advancements.')

        # Check output format
        ai_output = JSON.parse(props[:$ai_output_choices])
        expect(ai_output).to be_an(Array)
        expect(ai_output.first['role']).to eq('assistant')
        expect(ai_output.first['content']).to eq('AI is advancing rapidly...')

        # Check token counts
        expect(props[:$ai_input_tokens]).to eq(10)
        expect(props[:$ai_output_tokens]).to eq(50)

        expect(props).not_to have_key(:$ai_error)
      end
    end

    context 'when API key is missing (ConfigurationError)' do
      before do
        allow(Boxcars.configuration).to receive(:perplexity_api_key).and_return(nil)
      end

      it 'tracks an $ai_generation event with failure details' do
        expect do
          engine.client(prompt: prompt, inputs: inputs)
        end.to raise_error(Boxcars::ConfigurationError, /Perplexity API key not set/)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        props = dummy_observability_backend.tracked_events.first[:properties]
        expect(props[:$ai_is_error]).to be true
        expect(props[:$ai_error]).to match(/Perplexity API key not set/)
        expect(props[:$ai_provider]).to eq('perplexity_ai')
        expect(props[:$ai_http_status]).to eq(500)
      end
    end

    context 'when Faraday::Error (e.g., 401 Unauthorized) is raised' do
      let(:faraday_error) { Faraday::UnauthorizedError.new("Unauthorized", mock_faraday_error_response) }

      before do
        allow(mock_faraday_connection).to receive(:post).with('/chat/completions').and_raise(faraday_error)
      end

      it 'tracks an $ai_generation event with Faraday error details' do
        expect do
          engine.client(prompt: prompt, inputs: inputs)
        end.to raise_error(Faraday::UnauthorizedError)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        props = dummy_observability_backend.tracked_events.first[:properties]
        expect(props[:$ai_is_error]).to be true
        expect(props[:$ai_error]).to include('Unauthorized')
        expect(props[:$ai_http_status]).to eq(401)
        expect(props[:$ai_provider]).to eq('perplexity_ai')
        expect(props[:$ai_base_url]).to eq('https://api.perplexity.ai')
      end
    end

    describe '#run method' do
      it 'calls client and processes its output' do
        allow(mock_faraday_connection).to receive(:post).and_return(mock_faraday_response)
        result = engine.run("test question for perplexity")
        expect(result).to eq("AI is advancing rapidly...")

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        expect(dummy_observability_backend.tracked_events.first[:event]).to eq('$ai_generation')
      end
    end
  end
end
