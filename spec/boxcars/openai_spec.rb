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
  let(:openai_chat_cached_success_response) do
    openai_chat_success_response.merge(
      "usage" => {
        "prompt_tokens" => 9,
        "completion_tokens" => 12,
        "total_tokens" => 21,
        "prompt_tokens_details" => { "cached_tokens" => 4 }
      }
    )
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
  let(:openai_responses_cached_success_response) do
    {
      "id" => "resp_123",
      "object" => "response",
      "model" => "gpt-5-mini",
      "output" => [
        {
          "type" => "message",
          "content" => [
            {
              "type" => "output_text",
              "text" => { "value" => "Cached response output" }
            }
          ]
        }
      ],
      "usage" => {
        "input_tokens" => 30,
        "output_tokens" => 10,
        "total_tokens" => 40,
        "input_tokens_details" => { "cached_tokens" => 18 }
      }
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

  around do |example|
    original_builder = Boxcars::OpenAIClient.official_client_builder
    example.run
    Boxcars::OpenAIClient.official_client_builder = original_builder
  end

  before do
    Boxcars.configuration.observability_backend = dummy_observability_backend
    allow(Boxcars.configuration).to receive_messages(openai_access_token: api_key_param, organization_id: organization_id_param)
    Boxcars::OpenAIClient.official_client_builder = lambda do |access_token:, uri_base:, organization_id:, log_errors:|
      expect(access_token).to eq(api_key_param)
      expect(uri_base).to be_nil
      expect(organization_id).to eq(organization_id_param)
      expect(log_errors).to eq(true)
      mock_openai_client
    end
  end

  describe "defaults" do
    it "uses gpt-4o-mini as the default model" do
      expect(described_class.new.default_params[:model]).to eq("gpt-4o-mini")
    end

    it "rejects legacy prompts kwarg" do
      expect { described_class.new(prompts: [prompt]) }.to raise_error(Boxcars::ArgumentError, /prompts/)
    end
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

      it 'tracks cached input token observability fields when prompt cache details are present' do
        allow(mock_openai_client).to receive(:chat).and_return(openai_chat_cached_success_response)

        engine.client(prompt: prompt, inputs: inputs)

        props = dummy_observability_backend.tracked_events.first[:properties]
        expect(props[:$ai_input_tokens]).to eq(9)
        expect(props[:$ai_output_tokens]).to eq(12)
        expect(props[:$ai_input_cached_tokens]).to eq(4)
        expect(props[:$ai_input_uncached_tokens]).to eq(5)
      end
    end

    context 'when using the Responses API (e.g. gpt-5-mini)' do
      let(:engine_params) { { model: "gpt-5-mini" } }
      let(:mock_openai_responses_resource) { double("OpenAIResponsesResource") } # rubocop:disable RSpec/VerifiedDoubles

      before do
        allow(mock_openai_client).to receive(:responses).and_return(mock_openai_responses_resource)
        allow(mock_openai_responses_resource).to receive(:create).and_return(openai_responses_cached_success_response)
      end

      it 'tracks cached input token observability fields from Responses API usage' do
        engine.client(prompt: prompt, inputs: inputs)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        props = dummy_observability_backend.tracked_events.first[:properties]
        expect(props[:$ai_provider]).to eq("openai")
        expect(props[:$ai_model]).to eq("gpt-5-mini")
        expect(props[:$ai_input_tokens]).to eq(30)
        expect(props[:$ai_output_tokens]).to eq(10)
        expect(props[:$ai_input_cached_tokens]).to eq(18)
        expect(props[:$ai_input_uncached_tokens]).to eq(12)
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

    context 'when provider error (e.g., RateLimitError) is raised' do
      let(:openai_error) { StandardError.new("Rate limit reached for requests.").tap { |e| allow(e).to receive(:status).and_return(429) } }
      let(:engine_params) { { model: "gpt-4o-mini" } }

      before do
        allow(mock_openai_client).to receive(:chat).and_raise(openai_error) # Assuming chat model for this test
      end

      it 'tracks an llm_call event with provider error details' do
        expect do
          engine.client(prompt: prompt, inputs: inputs)
        end.to raise_error(StandardError, "Rate limit reached for requests.")

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

  describe '#generate method (usage aggregation + caching)' do
    let(:prompts_for_generate) do
      [
        [prompt, { product: "coffee shop" }],
        [prompt, { product: "tea house" }]
      ]
    end
    let(:responses_usage_payload) do
      {
        "id" => "resp_agg_1",
        "object" => "response",
        "output" => [
          {
            "type" => "message",
            "content" => [
              {
                "type" => "output_text",
                "text" => { "value" => "Responses API answer" }
              }
            ]
          }
        ],
        "usage" => {
          "input_tokens" => 100,
          "output_tokens" => 20,
          "total_tokens" => 120,
          "input_tokens_details" => { "cached_tokens" => 60 }
        }
      }
    end
    let(:chat_usage_payload) do
      {
        "choices" => [
          {
            "message" => { "role" => "assistant", "content" => "Chat Completions answer" },
            "finish_reason" => "stop"
          }
        ],
        "usage" => {
          "prompt_tokens" => 15,
          "completion_tokens" => 5,
          "total_tokens" => 20,
          "prompt_tokens_details" => { "cached_tokens" => 3 }
        }
      }
    end
    let(:aggregating_engine_class) do
      Class.new(described_class) do
        def initialize(mock_responses:, **kwargs)
          @mock_responses = mock_responses.dup
          super(**kwargs)
        end

        def client(*, **)
          @mock_responses.shift
        end
      end
    end
    let(:aggregating_engine) do
      aggregating_engine_class.new(
        mock_responses: [responses_usage_payload, chat_usage_payload],
        model: "gpt-5-mini",
        batch_size: 1
      )
    end

    it 'keeps token_usage and adds normalized cached usage details across OpenAI formats' do
      result = aggregating_engine.generate(prompts: prompts_for_generate)

      expect(result.engine_output[:token_usage]).to eq(
        "prompt_tokens" => 15,
        "completion_tokens" => 5,
        "total_tokens" => 140
      )
      expect(result.engine_output[:token_usage_details]).to eq(
        input_tokens: 115,
        output_tokens: 25,
        total_tokens: 140,
        cached_input_tokens: 63,
        uncached_input_tokens: 52
      )
      expect(result.engine_output[:raw_usage]).to eq(
        [responses_usage_payload["usage"], chat_usage_payload["usage"]]
      )
    end

    it 'supports single-prompt generation via generate_one' do
      single_engine = aggregating_engine_class.new(
        mock_responses: [chat_usage_payload],
        model: "gpt-4o-mini",
        batch_size: 1
      )
      result = single_engine.generate_one(prompt: prompt, inputs: { product: "coffee shop" })

      expect(result.generations.size).to eq(1)
      expect(result.generations.first.first.text).to eq("Chat Completions answer")
      expect(result.engine_output[:token_usage]).to eq(
        "prompt_tokens" => 15,
        "completion_tokens" => 5,
        "total_tokens" => 20
      )
    end

    it 'keeps multiple choices grouped under the same prompt generation' do
      multi_choice_payload = chat_usage_payload.merge(
        "choices" => [
          {
            "message" => { "role" => "assistant", "content" => "First option" },
            "finish_reason" => "stop"
          },
          {
            "message" => { "role" => "assistant", "content" => "Second option" },
            "finish_reason" => "stop"
          }
        ]
      )
      single_engine = aggregating_engine_class.new(
        mock_responses: [multi_choice_payload],
        model: "gpt-4o-mini",
        batch_size: 1
      )
      result = single_engine.generate(prompts: [[prompt, { product: "coffee shop" }]])

      expect(result.generations.size).to eq(1)
      expect(result.generations.first.map(&:text)).to eq(["First option", "Second option"])
    end
  end

  describe "deprecated backend kwargs" do
    it "raises when deprecated backend kwargs are passed to constructor" do
      expect do
        described_class.new(model: "gpt-4o-mini", openai_client_backend: :official_openai)
      end.to raise_error(Boxcars::ConfigurationError, /openai_client_backend/)
    end

    it "raises when deprecated backend kwargs are passed to #run" do
      expect(Boxcars::OpenAIClient).not_to receive(:build)

      expect do
        engine.run("Say hi", openai_client_backend: :ruby_openai, client_backend: :ruby_openai)
      end.to raise_error(Boxcars::ConfigurationError, /openai_client_backend.*client_backend|client_backend.*openai_client_backend/)
    end
  end
end
