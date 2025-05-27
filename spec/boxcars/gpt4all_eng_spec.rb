# frozen_string_literal: true

require 'spec_helper'
require 'boxcars/engine/gpt4all_eng'
require 'boxcars/observability'
require 'boxcars/prompt'
require 'gpt4all' # Ensure Gpt4all gem types are available for mocking

RSpec.describe Boxcars::Gpt4allEng do
  subject(:engine) { described_class.new(**engine_params) }

  let(:prompt_template) { "What is the main idea of %<concept>s?" }
  let(:prompt) { Boxcars::Prompt.new(template: prompt_template) }
  let(:inputs) { { concept: "existentialism" } }
  let(:engine_params) { { model_name: "custom-gpt4all-model" } } # Example of overriding default model name

  let(:mock_gpt4all_conversational_ai) { instance_double(Gpt4all::ConversationalAI) }
  let(:gpt4all_success_response_text) { "Existentialism emphasizes individual freedom and responsibility." }

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
    allow(Gpt4all::ConversationalAI).to receive(:new).and_return(mock_gpt4all_conversational_ai)
    allow(mock_gpt4all_conversational_ai).to receive(:prepare_resources).with(force_download: false).and_return(true)
    allow(mock_gpt4all_conversational_ai).to receive_messages(start_bot: true, stop_bot: true)
  end

  describe 'observability integration with Gpt4all::ConversationalAI' do
    context 'when interaction is successful' do
      before do
        allow(mock_gpt4all_conversational_ai).to receive(:prompt).and_return(gpt4all_success_response_text)
      end

      it 'tracks an llm_call event with correct properties' do
        # Example of passing kwargs that might be stored in @gpt4all_params but not directly used by the gem's prompt method
        engine.client(prompt: prompt, inputs: inputs, some_local_param: "value")

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        expect(tracked_event[:event]).to eq('llm_call')

        props = tracked_event[:properties]
        expect(props[:provider]).to eq(:gpt4all)
        expect(props[:model_name]).to eq("custom-gpt4all-model") # From engine_params
        expect(props[:success]).to be true
        expect(props[:duration_ms]).to be_a(Integer).and be >= 0
        expect(props[:inputs]).to eq(inputs)
        # api_call_parameters includes engine's params; prompt length is also added
        expect(props[:api_call_parameters]).to include(some_local_param: "value")
        expect(props[:api_call_parameters][:prompt_length]).to be_a(Integer)

        expect(props[:prompt_content]).to be_an(Array)
        expect(props[:prompt_content].first[:role].to_s).to eq("user")
        expect(props[:prompt_content].first[:content]).to include("What is the main idea of existentialism?")

        expect(props[:response_parsed_body]).to eq({ "text" => gpt4all_success_response_text })
        expect(props[:response_raw_body]).to eq(gpt4all_success_response_text)
        expect(props[:status_code]).to eq(200) # Inferred
        expect(props).not_to have_key(:error_message)
      end
    end

    context 'when Gpt4all::ConversationalAI.prompt raises an error' do
      let(:gpt4all_error) { StandardError.new("GPT4All model loading failed") }

      before do
        allow(mock_gpt4all_conversational_ai).to receive(:prompt).and_raise(gpt4all_error)
      end

      it 'tracks an llm_call event with error details' do
        expect do
          engine.client(prompt: prompt, inputs: inputs)
        end.to raise_error(StandardError, "GPT4All model loading failed")

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        props = dummy_observability_backend.tracked_events.first[:properties]
        expect(props[:success]).to be false
        expect(props[:error_message]).to eq("GPT4All model loading failed")
        expect(props[:error_class]).to eq("StandardError")
        expect(props[:provider]).to eq(:gpt4all)
        # No status_code for this kind of local error
      end
    end

    describe '#run method' do
      it 'calls client and processes its output' do
        allow(mock_gpt4all_conversational_ai).to receive(:prompt).and_return(gpt4all_success_response_text)
        result = engine.run("test question for gpt4all")
        expect(result).to eq(gpt4all_success_response_text)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        expect(dummy_observability_backend.tracked_events.first[:event]).to eq('llm_call')
      end
    end
  end
end
