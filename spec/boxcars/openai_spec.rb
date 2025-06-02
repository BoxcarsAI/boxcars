# frozen_string_literal: true

require 'spec_helper'
require 'boxcars/engine/openai'
require 'boxcars/prompt'
require 'openai' # Ensure OpenAI gem types are available

RSpec.describe Boxcars::Openai do
  subject(:engine) { described_class.new(**engine_params) }

  let(:prompt_template) { "Write a tagline for a %<product>s" } # Changed to use %{product}
  let(:prompt) { Boxcars::Prompt.new(template: prompt_template) }
  let(:inputs) { { product: "coffee shop" } }
  let(:api_key_param) { "test_openai_api_key" }
  let(:organization_id_param) { "test_org_id" }
  let(:engine_params) { {} }

  let(:mock_openai_client) { instance_double(OpenAI::Client) }
  let(:openai_chat_success_response) do
    {
      "id" => "chatcmpl-123",
      "object" => "chat.completion",
      "created" => 1_677_652_288,
      "model" => "gpt-4o-mini", # or whatever model is used
      "choices" => [{
        "index" => 0,
        "message" => {
          "role" => "assistant",
          "content" => "Your Daily Grind, Perfected."
        },
        "finish_reason" => "stop"
      }],
      "usage" => { "prompt_tokens" => 9, "completion_tokens" => 12, "total_tokens" => 21 }
    }
  end
  let(:openai_completion_success_response) do
    {
      "id" => "cmpl-123",
      "object" => "text_completion",
      "created" => 1_677_652_288,
      "model" => "text-davinci-003", # example completion model
      "choices" => [{
        "text" => "Your Daily Grind, Perfected.",
        "index" => 0,
        "logprobs" => nil,
        "finish_reason" => "stop"
      }],
      "usage" => { "prompt_tokens" => 5, "completion_tokens" => 7, "total_tokens" => 12 }
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
    allow(Boxcars.configuration).to receive_messages(openai_access_token: api_key_param, organization_id: organization_id_param)
    allow(OpenAI::Client).to receive(:new)
      .with(access_token: api_key_param, organization_id: organization_id_param, log_errors: true)
      .and_return(mock_openai_client)
  end

  describe 'observability integration with direct OpenAI client usage' do
    context 'when using a chat model' do
      let(:engine_params) { { model: "gpt-4o-mini" } } # Ensure it's a chat model

      before do
        allow(mock_openai_client).to receive(:chat).and_return(openai_chat_success_response)
      end

      it 'tracks an llm_call event with correct properties' do
        engine.client(prompt: prompt, inputs: inputs, temperature: 0.7)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        expect(tracked_event[:event]).to eq("$ai_generation")

        props = tracked_event[:properties]
        puts props.inspect # Debugging output to see properties
        expect(props[:$ai_provider]).to eq("openai")
        expect(props[:$ai_model]).to eq("gpt-4o-mini")
        expect(props[:$ai_is_error]).to be false
        expect(props[:$ai_http_status]).to eq(200) # Inferred on success
        expect(props).not_to have_key(:error_message)
      end
    end

    context 'when using a completion model' do
      let(:engine_params) { { model: "text-davinci-003" } } # Ensure it's a completion model

      before do
        allow(mock_openai_client).to receive(:completions).and_return(openai_completion_success_response)
      end

      it 'tracks an llm_call event with correct properties for completion' do
        engine.client(prompt: prompt, inputs: inputs, max_tokens: 150)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        props = tracked_event[:properties]
        expect(props[:$ai_provider]).to eq("openai")
        expect(props[:$ai_model]).to eq("text-davinci-003")
        expect(props[:$ai_is_error]).to be false
        expect(props[:$ai_input]).to match(/Write a tagline for a coffee shop/)
      end
    end

    context 'when API key is missing (ConfigurationError)' do
      before do
        allow(Boxcars.configuration).to receive(:openai_access_token).and_raise(Boxcars::ConfigurationError.new("OpenAI API key not set"))
      end

      it 'tracks an llm_call event with failure details' do
        expect do
          engine.client(prompt: prompt, inputs: inputs)
        end.to raise_error(Boxcars::ConfigurationError, /OpenAI API key not set/)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        props = dummy_observability_backend.tracked_events.first[:properties]
        expect(props[:$ai_is_error]).to be true
        expect(props[:$ai_error]).to match(/OpenAI API key not set/)
        expect(props[:$ai_provider]).to eq("openai")
      end
    end

    context 'when OpenAI::Error (e.g., RateLimitError) is raised' do
      let(:openai_error) { OpenAI::Error.new("Rate limit reached for requests.").tap { |e| allow(e).to receive(:http_status).and_return(429) } }
      let(:engine_params) { { model: "gpt-4o-mini" } }

      before do
        allow(mock_openai_client).to receive(:chat).and_raise(openai_error) # Assuming chat model for this test
      end

      it 'tracks an llm_call event with OpenAI error details' do
        expect do
          engine.client(prompt: prompt, inputs: inputs)
        end.to raise_error(OpenAI::Error, "Rate limit reached for requests.")

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        props = dummy_observability_backend.tracked_events.first[:properties]
        expect(props[:$ai_is_error]).to be true
        expect(props[:$ai_error]).to eq("Rate limit reached for requests.")
        expect(props[:$ai_http_status]).to eq(429)
        expect(props[:$ai_provider]).to eq("openai")
      end
    end

    describe '#run method' do
      let(:engine_params) { { model: "gpt-4o-mini" } }

      it 'calls client and processes its output, ensuring observability is triggered via client' do
        allow(mock_openai_client).to receive(:chat).and_return(openai_chat_success_response)
        result = engine.run("test question for openai")
        expect(result).to eq("Your Daily Grind, Perfected.")

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        expect(dummy_observability_backend.tracked_events.first[:event]).to eq("$ai_generation")
      end
    end
  end
end
