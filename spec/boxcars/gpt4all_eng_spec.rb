# frozen_string_literal: true

require 'spec_helper'
require 'boxcars/engine/gpt4all_eng'
require 'boxcars/prompt'

unless defined?(Gpt4all::ConversationalAI)
  module Gpt4all
    class ConversationalAI
      def prepare_resources(*)
      end

      def start_bot
      end

      def stop_bot
      end

      def prompt(*)
      end
    end
  end
end

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
    Boxcars.configuration.observability_backend = dummy_observability_backend
    allow(Gpt4all::ConversationalAI).to receive(:new).and_return(mock_gpt4all_conversational_ai)
    allow(mock_gpt4all_conversational_ai).to receive(:prepare_resources).with(force_download: false).and_return(true)
    allow(mock_gpt4all_conversational_ai).to receive_messages(start_bot: true, stop_bot: true)
  end

  describe 'observability integration with Gpt4all::ConversationalAI' do
    it "raises a setup error when gpt4all is unavailable" do
      missing_gpt4all_engine = Class.new(described_class) do
        private

        def gpt4all_available?
          false
        end
      end.new(**engine_params)

      expect do
        missing_gpt4all_engine.client(prompt: prompt, inputs: inputs)
      end.to raise_error(Boxcars::ConfigurationError, /requires the `gpt4all` gem/)
    end

    context 'when interaction is successful' do
      before do
        allow(mock_gpt4all_conversational_ai).to receive(:prompt).and_return(gpt4all_success_response_text)
      end

      it 'tracks an $ai_generation event with correct properties' do
        # Example of passing kwargs that might be stored in @gpt4all_params but not directly used by the gem's prompt method
        engine.client(prompt: prompt, inputs: inputs, some_local_param: "value")

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        expect(tracked_event[:event]).to eq('$ai_generation')

        props = tracked_event[:properties]
        expect(props[:$ai_provider]).to eq('gpt4all')
        expect(props[:$ai_model]).to eq("custom-gpt4all-model") # From engine_params
        expect(props[:$ai_is_error]).to be false
        expect(props[:$ai_latency]).to be_a(Float).and be >= 0
        expect(props[:$ai_trace_id]).to be_a(String)
        expect(props[:$ai_http_status]).to eq(200) # Inferred
        expect(props[:$ai_base_url]).to eq("https://api.gpt4all.com/v1")

        # Check input format
        ai_input = JSON.parse(props[:$ai_input])
        expect(ai_input).to be_an(Array)
        expect(ai_input.first['role']).to eq("user")
        expect(ai_input.first['content']).to include("What is the main idea of existentialism?")

        # Check output format
        ai_output_choices = JSON.parse(props[:$ai_output_choices])
        expect(ai_output_choices).to be_an(Array)
        expect(ai_output_choices.first['role']).to eq("assistant")
        expect(ai_output_choices.first['content']).to eq(gpt4all_success_response_text)

        expect(props).not_to have_key(:$ai_error)
      end
    end

    context 'when Gpt4all::ConversationalAI.prompt raises an error' do
      let(:gpt4all_error) { StandardError.new("GPT4All model loading failed") }

      before do
        allow(mock_gpt4all_conversational_ai).to receive(:prompt).and_raise(gpt4all_error)
      end

      it 'tracks an $ai_generation event with error details' do
        expect do
          engine.client(prompt: prompt, inputs: inputs)
        end.to raise_error(StandardError, "GPT4All model loading failed")

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        props = dummy_observability_backend.tracked_events.first[:properties]
        expect(props[:$ai_is_error]).to be true
        expect(props[:$ai_error]).to eq("GPT4All model loading failed")
        expect(props[:$ai_provider]).to eq('gpt4all')
        expect(props[:$ai_http_status]).to eq(500) # Error status
      end
    end

    describe '#run method' do
      it 'calls client and processes its output' do
        allow(mock_gpt4all_conversational_ai).to receive(:prompt).and_return(gpt4all_success_response_text)
        result = engine.run("test question for gpt4all")
        expect(result).to eq(gpt4all_success_response_text)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        expect(dummy_observability_backend.tracked_events.first[:event]).to eq('$ai_generation')
      end
    end
  end
end
