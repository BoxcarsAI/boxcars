# frozen_string_literal: true

require 'spec_helper'
require 'boxcars/engine/anthropic'
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
  let(:anthropic_success_response_symbolized) do
    {
      id: "msg_01AgsP9Nyr82xWmc35n9YgZs",
      type: "message",
      role: "assistant",
      content: [{ type: "text", text: "Why did the robot go to therapy? To de-stress and debug its feelings!" }],
      model: "claude-3-5-sonnet-20240620",
      stop_reason: "end_turn",
      stop_sequence: nil,
      usage: { input_tokens: 15, output_tokens: 23 }
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
    Boxcars.configuration.observability_backend = dummy_observability_backend
    allow(Boxcars.configuration).to receive(:anthropic_api_key).and_return(api_key_param)
    allow(Anthropic::Client).to receive(:new).with(access_token: api_key_param).and_return(mock_anthropic_client)
  end

  describe 'request parameter compatibility' do
    %w[claude-sonnet-5 claude-opus-5 claude-fable-5].each do |model|
      it "omits unsupported sampling params for #{model}" do
        captured_params = nil
        allow(mock_anthropic_client).to receive(:messages) do |parameters:|
          captured_params = parameters
          anthropic_success_response
        end

        described_class.new(model:).client(
          prompt:,
          inputs:,
          temperature: 0,
          top_p: 0.5,
          top_k: 10
        )

        expect(captured_params).to include(model:)
        expect(captured_params).not_to include(:temperature, :top_p, :top_k)
      end
    end

    it 'omits default unsupported sampling params from the final request params' do
      captured_params = nil
      allow(mock_anthropic_client).to receive(:messages) do |parameters:|
        captured_params = parameters
        anthropic_success_response
      end

      described_class.new(model: "claude-opus-4-7").client(prompt: prompt, inputs: inputs)

      expect(captured_params).to include(model: "claude-opus-4-7")
      expect(captured_params).not_to include(:temperature, :top_p, :top_k)
    end

    it 'omits explicit unsupported sampling params from the final request params' do
      captured_params = nil
      allow(mock_anthropic_client).to receive(:messages) do |parameters:|
        captured_params = parameters
        anthropic_success_response
      end

      described_class.new(
        model: "claude-opus-4-7",
        temperature: 0,
        top_p: 0.5,
        top_k: 10
      ).client(prompt: prompt, inputs: inputs)

      expect(captured_params).to include(model: "claude-opus-4-7")
      expect(captured_params).not_to include(:temperature, :top_p, :top_k)
    end

    it 'omits unsupported sampling params for Opus 4.7 snapshot and variant ids' do
      captured_params = nil
      allow(mock_anthropic_client).to receive(:messages) do |parameters:|
        captured_params = parameters
        anthropic_success_response
      end

      described_class.new(
        model: "claude-opus-4-7-20260501",
        temperature: 0,
        top_p: 0.5,
        top_k: 10
      ).client(prompt: prompt, inputs: inputs)

      expect(captured_params).to include(model: "claude-opus-4-7-20260501")
      expect(captured_params).not_to include(:temperature, :top_p, :top_k)
    end

    it 'does not treat unrelated model names as Claude 5 snapshots' do
      captured_params = nil
      allow(mock_anthropic_client).to receive(:messages) do |parameters:|
        captured_params = parameters
        anthropic_success_response
      end

      described_class.new(model: "claude-sonnet-50", temperature: 0.4).client(prompt:, inputs:)

      expect(captured_params).to include(model: "claude-sonnet-50", temperature: 0.4)
    end

    it 'preserves the existing default temperature for older Claude models' do
      captured_params = nil
      allow(mock_anthropic_client).to receive(:messages) do |parameters:|
        captured_params = parameters
        anthropic_success_response
      end

      described_class.new(model: "claude-3-5-sonnet-20240620").client(prompt: prompt, inputs: inputs)

      expect(captured_params).to include(
        model: "claude-3-5-sonnet-20240620",
        temperature: 0.1
      )
    end
  end

  describe 'Opus sampling compatibility' do
    let(:requests) { [] }
    let(:sampling) { { temperature: 0.2, top_p: 0.5, top_k: 10 } }

    before do
      allow(mock_anthropic_client).to receive(:messages) do |parameters:|
        requests << parameters
        anthropic_success_response
      end
    end

    %w[claude-opus-4-7 claude-opus-5-5 claude-opus-5-5-20261001].each do |model|
      %i[engine json_engine].each do |factory|
        ["default", "explicit", "string-keyed"].each do |parameter_style|
          it "omits #{parameter_style} sampling options for #{model} through #{factory}" do
            options = case parameter_style
                      when "default" then {}
                      when "explicit" then sampling
                      else sampling.transform_keys(&:to_s)
                      end
            configured_engine = Boxcars::Engines.public_send(factory, model:, **options)

            expect(configured_engine.llm_params).not_to include(:temperature, :top_p, :top_k, "temperature", "top_p", "top_k")
            configured_engine.client(prompt:, inputs:)

            expect(requests.last).to include(model:)
            expect(requests.last).not_to include(:temperature, :top_p, :top_k, "temperature", "top_p", "top_k", :response_format)
          end
        end
      end
    end

    it 'uses a string-keyed constructor model when filtering sampling options' do
      options = { "model" => "claude-opus-5-5", **sampling.transform_keys(&:to_s) }.freeze
      configured_engine = described_class.new(**options)

      expect(configured_engine.llm_params).to include(model: "claude-opus-5-5")
      expect(configured_engine.llm_params).not_to include(:temperature, :top_p, :top_k, "temperature", "top_p", "top_k", "model")
      configured_engine.client(prompt:, inputs:)

      expect(requests.last).to include(model: "claude-opus-5-5")
      expect(requests.last).not_to include(:temperature, :top_p, :top_k, "temperature", "top_p", "top_k", "model")
    end

    %w[claude-opus-4-7 claude-opus-5-5].each do |model|
      [false, true].each do |string_keys|
        it "filters per-request model and sampling overrides for #{model} (string keys: #{string_keys})" do
          configured_engine = described_class.new(model: "claude-opus-4-6", **sampling)
          original_params = configured_engine.llm_params.dup
          overrides = { model:, **sampling }
          overrides = overrides.transform_keys(&:to_s) if string_keys
          overrides.freeze

          configured_engine.client(prompt:, inputs:, **overrides)

          expect(requests.last).to include(model:)
          expect(requests.last).not_to include(:temperature, :top_p, :top_k, "temperature", "top_p", "top_k", "model")
          expect(configured_engine.llm_params).to eq(original_params)
        end
      end
    end

    it 'filters sampling overrides even when the model does not change' do
      configured_engine = described_class.new(model: "claude-opus-5-5")
      configured_engine.client(prompt:, inputs:, **sampling, **sampling.transform_keys(&:to_s))

      expect(requests.last).not_to include(:temperature, :top_p, :top_k, "temperature", "top_p", "top_k")
    end

    it 'preserves explicit sampling when a request switches to a supporting model' do
      configured_engine = described_class.new(model: "claude-opus-5-5")
      configured_engine.client(prompt:, inputs:, **{ "model" => "claude-opus-4-6", **sampling.transform_keys(&:to_s) })

      expect(requests.last).to include(model: "claude-opus-4-6", temperature: 0.2, top_p: 0.5, top_k: 10)
      expect(requests.last).not_to include("model", "temperature", "top_p", "top_k")
      expect(configured_engine.llm_params).to include(model: "claude-opus-5-5")
    end

    it 'preserves sampling for supporting models and unrelated model names' do
      %w[claude-opus-4-6 claude-opus-4-70 claude-opus-50].each do |model|
        described_class.new(model:, **sampling).client(prompt:, inputs:, temperature: 0.3)

        expect(requests.last).to include(model:, temperature: 0.3, top_p: 0.5, top_k: 10)
      end
    end

    it 'returns schema-valid JSON through the JSON engine boxcar path' do
      allow(mock_anthropic_client).to receive(:messages) do |parameters:|
        requests << parameters
        anthropic_success_response.merge("content" => [
                                           { "type" => "thinking", "thinking" => "" },
                                           { "type" => "text", "text" => '{"answer":"OK"}' }
                                         ])
      end
      configured_engine = Boxcars::Engines.json_engine(model: "claude-opus-5-5", **sampling)
      boxcar = Boxcars::JSONEngineBoxcar.new(
        engine: configured_engine,
        json_schema: { type: "object", properties: { answer: { type: "string" } }, required: ["answer"], additionalProperties: false }
      )

      expect(boxcar.run("Reply with OK")).to eq("answer" => "OK")
      expect(requests.last).not_to include(:temperature, :top_p, :top_k, :response_format)
    end
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

      it 'tracks an llm_call event when the provider response uses symbol keys' do
        allow(mock_anthropic_client).to receive(:messages).and_return(anthropic_success_response_symbolized)

        engine.client(prompt: prompt, inputs: inputs, temperature: 0.7, max_tokens: 100)

        props = dummy_observability_backend.tracked_events.first[:properties]
        ai_output = JSON.parse(props[:$ai_output_choices])
        expect(ai_output.first).to include("role" => "assistant")
        expect(ai_output.first["content"]).to include("Why did the robot go to therapy?")
        expect(props[:$ai_input_tokens]).to eq(15)
        expect(props[:$ai_output_tokens]).to eq(23)
      end

      it 'extracts text when a thinking block precedes the text block' do
        json_text = '{"answer":"Austin","rationale":"Strong venues","ranked_items":[]}'
        response = anthropic_success_response.merge(
          "content" => [
            { "type" => "thinking", "thinking" => "..." },
            { "type" => "text", "text" => json_text }
          ],
          "usage" => { "input_tokens" => 11, "output_tokens" => 7 }
        )
        allow(mock_anthropic_client).to receive(:messages).and_return(response)

        result = engine.client(prompt: prompt, inputs: inputs)

        expect(result["completion"]).to eq(json_text)
        expect(result.dig("choices", 0, "text")).to eq(json_text)
        expect(result.dig("usage", "prompt_tokens")).to eq(11)
        expect(result.dig("usage", "completion_tokens")).to eq(7)
        expect(result.dig("usage", "total_tokens")).to eq(18)
      end

      it 'joins multiple text-bearing content blocks' do
        sdk_text_block = Struct.new(:text).new("third")
        response = anthropic_success_response.merge(
          "content" => [
            { type: "text", text: "first" },
            "second",
            sdk_text_block
          ]
        )
        allow(mock_anthropic_client).to receive(:messages).and_return(response)

        result = engine.client(prompt: prompt, inputs: inputs)

        expect(result["completion"]).to eq("first\nsecond\nthird")
        expect(result.dig("choices", 0, "text")).to eq("first\nsecond\nthird")
      end

      it 'records an error when a successful response contains no text blocks' do
        response = anthropic_success_response.merge(
          "content" => [
            { "type" => "thinking", "thinking" => "..." }
          ]
        )
        allow(mock_anthropic_client).to receive(:messages).and_return(response)

        expect do
          engine.client(prompt: prompt, inputs: inputs)
        end.to raise_error(Boxcars::Error, /no text content/)

        props = dummy_observability_backend.tracked_events.first[:properties]
        expect(props[:$ai_is_error]).to be true
        expect(props[:$ai_error]).to include('no text content')
      end

      it 'keeps extracting existing simple text-first responses' do
        result = engine.client(prompt: prompt, inputs: inputs)

        expect(result["completion"]).to eq("Why did the robot go to therapy? To de-stress and debug its feelings!")
        expect(result.dig("choices", 0, "text")).to eq("Why did the robot go to therapy? To de-stress and debug its feelings!")
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
        expect(props[:$ai_error]).to include('Anthropic API key not set')
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
