# frozen_string_literal: true

require 'spec_helper'
require 'boxcars/engine/cohere' # Make sure this path is correct
require 'boxcars/observability'
require 'boxcars/prompt'

# Stub Intelligence::ChatResponse if not already globally available in spec_helper
# or if specific stubs are needed for Cohere adapter.
unless defined?(Intelligence::ChatResponse)
  module Intelligence
    class ChatResponse
      def success?
      end

      def body
      end

      def status
      end

      def reason_phrase
      end
    end
  end
end

RSpec.describe Boxcars::Cohere do
  subject(:engine) { described_class.new(**engine_params) }

  let(:prompt_template) { "Translate this: {{text}}" }
  let(:prompt) { Boxcars::Prompt.new(template: prompt_template) }
  let(:inputs) { { text: "hello world" } }
  let(:api_key_param) { "test_cohere_api_key" } # Can be overridden or fetched from config mock

  let(:mock_intelligence_adapter_class) { class_double(Intelligence::Adapter::Base).as_stubbed_const }
  let(:mock_intelligence_adapter) { instance_double(Intelligence::Adapter::Base) }
  let(:mock_intelligence_request) { instance_double(Intelligence::ChatRequest) } # Assuming IntelligenceBase uses ChatRequest
  let(:mock_chat_response) do
    instance_double(Intelligence::ChatResponse,
                    success?: true,
                    body: { text: "hola mundo" }.to_json, # Example Cohere-like response
                    status: 200,
                    reason_phrase: "OK")
  end
  let(:mock_request_chat_call) do
    allow(mock_intelligence_request).to receive(:chat).and_return(mock_chat_response)
  end

  let(:engine_params) { {} } # Default, can be overridden in contexts

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
    # Reset and set observability backend
    Boxcars::Observability.backend = dummy_observability_backend

    # Mock Boxcars configuration for API key
    allow(Boxcars.configuration).to receive(:cohere_api_key).and_return(api_key_param)

    # Mock the Intelligence gem interactions for :cohere provider
    allow(Intelligence::Adapter).to receive(:[]).with(:cohere).and_return(mock_intelligence_adapter_class)
    allow(mock_intelligence_adapter_class).to receive(:new).with(api_key_param).and_return(mock_intelligence_adapter)
    allow(Intelligence::ChatRequest).to receive(:new).with(adapter: mock_intelligence_adapter).and_return(mock_intelligence_request)
    allow(mock_request_chat_call) # Default mock for successful chat
  end

  describe 'observability integration through IntelligenceBase' do
    context 'when API call is successful' do
      it 'tracks an llm_call event with correct properties' do
        # rubocop:disable RSpec/SubjectStub
        allow(engine).to receive(:extract_answer).and_return("hola mundo")
        # rubocop:enable RSpec/SubjectStub

        engine.client(prompt: prompt, inputs: inputs, temperature: 0.7)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        expect(tracked_event[:event]).to eq('llm_call')

        props = tracked_event[:properties]
        expect(props[:provider]).to eq(:cohere)
        expect(props[:model_name]).to eq("command-r-plus") # From DEFAULT_PARAMS
        expect(props[:success]).to be true
        expect(props[:duration_ms]).to be_a(Integer).and be >= 0
        expect(props[:status_code]).to eq(200)
        expect(props[:reason_phrase]).to eq("OK")
        expect(props[:inputs]).to eq(inputs)
        expect(props[:api_call_parameters]).to include(model: "command-r-plus", temperature: 0.7)
        expect(props[:prompt_content]).to be_an(Array)
        expect(props[:response_parsed_body]).to eq({ "text" => "hola mundo" }) # Based on mock_chat_response
        expect(props[:response_raw_body]).to eq({ text: "hola mundo" }.to_json)
        expect(props).not_to have_key(:error_message)
        expect(props).not_to have_key(:error_class)
      end

      it 'uses call-specific model params if provided' do
        # rubocop:disable RSpec/SubjectStub
        allow(engine).to receive(:extract_answer).and_return("hola mundo")
        # rubocop:enable RSpec/SubjectStub
        engine.client(prompt: prompt, inputs: inputs, model: "custom-cohere-model")
        props = dummy_observability_backend.tracked_events.first[:properties]
        expect(props[:model_name]).to eq("custom-cohere-model")
        expect(props[:api_call_parameters]).to include(model: "custom-cohere-model")
      end
    end

    context 'when API key is missing' do
      before do
        allow(Boxcars.configuration).to receive(:cohere_api_key).and_return(nil)
        # We also need to ensure the adapter new call doesn't happen if api_key is nil,
        # or that lookup_provider_api_key in engine correctly raises before adapter init.
        # IntelligenceBase's _prepare_request_data should raise before adapter init.
      end

      it 'tracks an llm_call event with failure details' do
        expect do
          engine.client(prompt: prompt, inputs: inputs)
        end.to raise_error(Boxcars::Error, /No API key found for cohere/)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        props = tracked_event[:properties]

        expect(props[:success]).to be false
        expect(props[:error_message]).to match(/No API key found for cohere/)
        expect(props[:error_class]).to eq("Boxcars::Error")
        expect(props[:provider]).to eq(:cohere)
      end
    end

    context 'when API call fails (e.g., network error or API error status)' do
      before do
        allow(mock_intelligence_request).to receive(:chat).and_raise(StandardError.new("Cohere Network timeout"))
      end

      it 'tracks an llm_call event with error details from raised exception' do
        expect do
          engine.client(prompt: prompt, inputs: inputs)
        end.to raise_error(StandardError, "Cohere Network timeout")

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        props = tracked_event[:properties]

        expect(props[:success]).to be false
        expect(props[:error_message]).to eq("Cohere Network timeout")
        expect(props[:error_class]).to eq("StandardError")
        expect(props[:error_backtrace]).to be_a(String)
        expect(props[:provider]).to eq(:cohere)
      end
    end

    context 'when API returns a non-successful status' do
      before do
        allow(mock_chat_response).to receive_messages(success?: false, status: 401, reason_phrase: "Unauthorized", body: { message: "Invalid API key" }.to_json)
        # Redefine mock_request_chat_call for this context
        allow(mock_intelligence_request).to receive(:chat).and_return(mock_chat_response)
      end

      it 'tracks an llm_call event with failure details from response object' do
        expect do
          engine.client(prompt: prompt, inputs: inputs)
        end.to raise_error(Boxcars::Error, /Unauthorized/)

        expect(dummy_observability_backend.tracked_events.size).to eq(1)
        tracked_event = dummy_observability_backend.tracked_events.first
        props = tracked_event[:properties]

        expect(props[:success]).to be false
        expect(props[:status_code]).to eq(401)
        expect(props[:reason_phrase]).to eq("Unauthorized")
        expect(props[:response_raw_body]).to eq({ message: "Invalid API key" }.to_json)
        expect(props[:response_parsed_body]).to be_nil # Since success? was false
        expect(props[:error_message]).to eq("Unauthorized")
        expect(props[:error_class]).to eq("Boxcars::Error")
        expect(props[:provider]).to eq(:cohere)
      end
    end

    describe '#run method' do
      it 'calls client and processes its output, ensuring observability is triggered via client' do
        # rubocop:disable RSpec/SubjectStub
        allow(engine).to receive(:extract_answer).with(JSON.parse(mock_chat_response.body)).and_return("final answer from cohere")
        # rubocop:enable RSpec/SubjectStub

        result = engine.run("test question")
        expect(result).to eq("final answer from cohere")

        expect(dummy_observability_backend.tracked_events.size).to eq(1) # Tracked by the client call within run
        expect(dummy_observability_backend.tracked_events.first[:event]).to eq('llm_call')
        expect(dummy_observability_backend.tracked_events.first[:properties][:provider]).to eq(:cohere)
      end
    end
  end
end
