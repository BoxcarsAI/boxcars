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
        expect(tracked_event[:event]).to eq('llm_call')

        props = tracked_event[:properties]
        expect(props[:provider]).to eq(:anthropic)
        expect(props[:model_name]).to eq("claude-3-5-sonnet-20240620") # From DEFAULT_PARAMS or actual call
        expect(props[:success]).to be true
        expect(props[:duration_ms]).to be_a(Integer).and be >= 0
        expect(props[:inputs]).to eq(inputs)
        # api_call_parameters should reflect what was passed to client() before transformation
        expect(props[:api_call_parameters]).to include(model: "claude-3-5-sonnet-20240620", temperature: 0.7, max_tokens: 100)
        # anthropic_request_parameters could be checked if logged, e.g. to verify max_tokens_to_sample mapping
        expect(props[:prompt_content]).to be_an(Array)
        expect(props[:prompt_content].first[:role].to_s).to eq("user") # Or system if prompt starts that way
        expect(props[:prompt_content].first[:content]).to include("Tell me a joke about {{topic}}")

        expect(props[:response_parsed_body]).to eq(anthropic_success_response)
        expect(props[:response_raw_body]).to eq(JSON.pretty_generate(anthropic_success_response))
        expect(props[:status_code]).to be_nil # Anthropic gem abstracts HTTP status on success
        expect(props).not_to have_key(:error_message)
        expect(props).not_to have_key(:error_class)
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
        props = dummy_observability_backend.tracked_events.first[:properties]
        expect(props[:success]).to be false
        expect(props[:error_message]).to match(/Anthropic API key not set/)
        expect(props[:error_class]).to eq("Boxcars::ConfigurationError")
        expect(props[:provider]).to eq(:anthropic)
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
        props = dummy_observability_backend.tracked_events.first[:properties]
        expect(props[:success]).to be false
        expect(props[:error_message]).to eq("Invalid API Key")
        expect(props[:error_class]).to eq("Anthropic::Error")
        expect(props[:status_code]).to eq(500) # From our mapping in client
        expect(props[:provider]).to eq(:anthropic)
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
        props = dummy_observability_backend.tracked_events.first[:properties]
        expect(props[:success]).to be false
        expect(props[:error_message]).to eq("Rate limit exceeded")
        expect(props[:error_class]).to eq("Anthropic::Error")
        expect(props[:status_code]).to eq(500) # From our mapping in client
        expect(props[:provider]).to eq(:anthropic)
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
        props = dummy_observability_backend.tracked_events.first[:properties]
        expect(props[:success]).to be false
        expect(props[:error_message]).to eq("Generic network issue")
        expect(props[:error_class]).to eq("StandardError")
        expect(props[:provider]).to eq(:anthropic)
      end
    end

    describe '#run method' do
      it 'calls client and processes its output, ensuring observability is triggered via client' do
        allow(mock_anthropic_client).to receive(:messages).and_return(anthropic_success_response)
        result = engine.run("test question") # inputs will be {}
        expect(result).to eq("Why did the robot go to therapy? To de-stress and debug its feelings!")

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        expect(dummy_observability_backend.tracked_events.first[:event]).to eq('llm_call')
        expect(dummy_observability_backend.tracked_events.first[:properties][:provider]).to eq(:anthropic)
      end
    end
  end
end
