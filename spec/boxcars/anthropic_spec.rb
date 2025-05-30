# frozen_string_literal: true

require 'spec_helper'
require 'boxcars/engine/anthropic'
require 'boxcars/observability'
require 'boxcars/prompt'
require 'anthropic' # Ensure the actual Anthropic gem types are available for mocking if needed

RSpec.describe Boxcars::Anthropic do
  subject(:engine) { described_class.new(**engine_params) }

  let(:prompt_template) { "Tell me a joke about {{topic}}" }
  let(:prompt) { Boxcars::Prompt.new(template: prompt_template) }
  let(:inputs) { { topic: "robots" } }
  let(:api_key_param) { "test_anthropic_api_key" }
  let(:engine_params) { {} }

  let(:mock_anthropic_client) { instance_double(Anthropic::Client) }
  let(:anthropic_success_response) do
    {
      "id" => "msg_01AgsP9Nyr82xWmc35n9YgZs",
      "type" => "message",
      "role" => "assistant",
      "content" => [{ "type" => "text", "text" => "Why did the robot go to therapy? To de-stress and debug its feelings!" }],
      "model" => "claude-3-5-sonnet-20240620",
      "stop_reason" => "end_turn",
      "stop_sequence" => nil,
      "usage" => { "input_tokens" => 15, "output_tokens" => 23 }
    }
  end
  let(:anthropic_error_response_body) { { "type" => "error", "error" => { "type" => "invalid_request_error", "message" => "Invalid parameter." } } }

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
    allow(Boxcars.configuration).to receive(:anthropic_api_key).and_return(api_key_param)
    allow(Anthropic::Client).to receive(:new).with(access_token: api_key_param).and_return(mock_anthropic_client)
  end

  describe 'observability integration with direct Anthropic client usage' do
    context 'when API call is successful' do
      before do
        allow(mock_anthropic_client).to receive(:messages).and_return(anthropic_success_response)
      end

      it 'tracks an llm_call event with correct properties' do
        engine.client(prompt: prompt, inputs: inputs, temperature: 0.7, max_tokens: 100) # max_tokens will be mapped

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        expect(tracked_event[:event]).to eq('$ai_generation')

        props = tracked_event[:properties]
        expect(props[:$ai_provider]).to eq('anthropic')
        expect(props[:$ai_model]).to eq("claude-3-5-sonnet-20240620") # From DEFAULT_PARAMS or actual call
        expect(props[:$ai_is_error]).to be false
        expect(props[:$ai_latency]).to be_a(Float).and be >= 0
        expect(props[:$ai_input_tokens]).to eq(15)
        expect(props[:$ai_output_tokens]).to eq(23)
        expect(props[:$ai_http_status]).to eq(200)
        expect(props[:$ai_base_url]).to eq('https://api.anthropic.com/v1')

        # Check input format
        ai_input = JSON.parse(props[:$ai_input])
        expect(ai_input).to be_an(Array)
        expect(ai_input.first['role']).to eq('user')
        expect(ai_input.first['content']).to include('Tell me a joke about {{topic}}')

        # Check output format
        ai_output = JSON.parse(props[:$ai_output_choices])
        expect(ai_output).to be_an(Array)
        expect(ai_output.length).to be > 0
        expect(ai_output.first['role']).to eq('assistant')
        expect(ai_output.first['content']).to include('Why did the robot go to therapy?')

        expect(props).not_to have_key(:$ai_error)
      end
    end

    context 'when API key is missing (ConfigurationError)' do
      before do
        allow(Boxcars.configuration).to receive(:anthropic_api_key).and_raise(Boxcars::ConfigurationError.new("Anthropic API key not set"))
      end

      it 'tracks an llm_call event with failure details' do
        expect do
          engine.client(prompt: prompt, inputs: inputs)
        end.to raise_error(Boxcars::ConfigurationError, /Anthropic API key not set/)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        expect(tracked_event[:event]).to eq('$ai_generation')

        props = tracked_event[:properties]
        expect(props[:$ai_is_error]).to be true
        expect(props[:$ai_error]).to match(/Anthropic API key not set/)
        expect(props[:$ai_provider]).to eq('anthropic')
        expect(props[:$ai_http_status]).to eq(500)
      end
    end

    context 'when Anthropic::Error is raised' do
      before do
        allow(mock_anthropic_client).to receive(:messages).and_raise(Anthropic::Error.new("Invalid API Key"))
      end

      it 'tracks an llm_call event with error details' do
        expect do
          engine.client(prompt: prompt, inputs: inputs)
        end.to raise_error(Anthropic::Error, "Invalid API Key")

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        expect(tracked_event[:event]).to eq('$ai_generation')

        props = tracked_event[:properties]
        expect(props[:$ai_is_error]).to be true
        expect(props[:$ai_error]).to eq("Invalid API Key")
        expect(props[:$ai_provider]).to eq('anthropic')
      end
    end

    context 'when Anthropic::Error is raised (rate limit)' do
      let(:rate_limit_error) { Anthropic::Error.new("Rate limit exceeded") }

      before do
        allow(mock_anthropic_client).to receive(:messages).and_raise(rate_limit_error)
      end

      it 'tracks an llm_call event with rate limit error details' do
        expect do
          engine.client(prompt: prompt, inputs: inputs)
        end.to raise_error(Anthropic::Error, "Rate limit exceeded")

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        expect(tracked_event[:event]).to eq('$ai_generation')

        props = tracked_event[:properties]
        expect(props[:$ai_is_error]).to be true
        expect(props[:$ai_error]).to eq("Rate limit exceeded")
        expect(props[:$ai_provider]).to eq('anthropic')
      end
    end

    context 'when a generic StandardError occurs during API call' do
      before do
        allow(mock_anthropic_client).to receive(:messages).and_raise(StandardError.new("Generic network issue"))
      end

      it 'tracks an llm_call event with generic error details' do
        expect do
          engine.client(prompt: prompt, inputs: inputs)
        end.to raise_error(StandardError, "Generic network issue")

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        expect(tracked_event[:event]).to eq('$ai_generation')

        props = tracked_event[:properties]
        expect(props[:$ai_is_error]).to be true
        expect(props[:$ai_error]).to eq("Generic network issue")
        expect(props[:$ai_provider]).to eq('anthropic')
      end
    end

    describe '#run method' do
      it 'calls client and processes its output, ensuring observability is triggered via client' do
        allow(mock_anthropic_client).to receive(:messages).and_return(anthropic_success_response)
        result = engine.run("test question") # inputs will be {}
        expect(result).to eq("Why did the robot go to therapy? To de-stress and debug its feelings!")

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        expect(tracked_event[:event]).to eq('$ai_generation')
        expect(tracked_event[:properties][:$ai_provider]).to eq('anthropic')
      end
    end
  end
end
