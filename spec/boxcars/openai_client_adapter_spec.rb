# frozen_string_literal: true

require "spec_helper"

RSpec.describe Boxcars::OpenAIClientAdapter do
  let(:raw_client) { double("OpenAI::Client") } # rubocop:disable RSpec/VerifiedDoubles

  around do |example|
    original_backend = Boxcars.configuration.openai_client_backend
    example.run
    Boxcars.configuration.openai_client_backend = original_backend
  end

  describe ".build" do
    it "builds an adapter around the OpenAI-compatible client factory" do
      expect(Boxcars::OpenAICompatibleClient).to receive(:build).with(
        access_token: "abc",
        uri_base: "https://example.test/v1",
        organization_id: "org_123",
        log_errors: true,
        backend: :ruby_openai
      ).and_return(raw_client)

      adapter = described_class.build(
        access_token: "abc",
        uri_base: "https://example.test/v1",
        organization_id: "org_123",
        log_errors: true,
        backend: :ruby_openai
      )

      expect(adapter).to be_a(described_class)
      expect(adapter.backend).to eq(:ruby_openai)
      expect(adapter.raw_client).to eq(raw_client)
    end

    it "uses configured backend when backend is omitted" do
      Boxcars.configuration.openai_client_backend = "ruby_openai"
      allow(Boxcars::OpenAICompatibleClient).to receive(:build).and_return(raw_client)

      adapter = described_class.build(access_token: "abc")

      expect(adapter.backend).to eq(:ruby_openai)
      expect(Boxcars::OpenAICompatibleClient).to have_received(:build).with(
        access_token: "abc",
        uri_base: nil,
        organization_id: nil,
        log_errors: nil,
        backend: :ruby_openai
      )
    end
  end

  describe "ruby-openai delegation" do
    subject(:adapter) { described_class.new(raw_client:, backend: :ruby_openai) }

    it "delegates chat_create" do
      expect(raw_client).to receive(:chat).with(parameters: { model: "gpt-4o" }).and_return("chat_result")

      expect(adapter.chat_create(parameters: { model: "gpt-4o" })).to eq("chat_result")
    end

    it "delegates completions_create" do
      expect(raw_client).to receive(:completions).with(parameters: { model: "text-davinci-003" }).and_return("completion_result")

      expect(adapter.completions_create(parameters: { model: "text-davinci-003" })).to eq("completion_result")
    end

    it "delegates embeddings_create" do
      expect(raw_client).to receive(:embeddings).with(parameters: { model: "text-embedding-3-small", input: "hello" }).and_return("embedding_result")

      expect(adapter.embeddings_create(parameters: { model: "text-embedding-3-small", input: "hello" })).to eq("embedding_result")
    end

    it "reports responses support when the raw client responds to responses" do
      allow(raw_client).to receive(:respond_to?).with(:responses).and_return(true)

      expect(adapter.supports_responses_api?).to be(true)
    end

    it "raises a clear error when responses are not supported" do
      allow(raw_client).to receive(:respond_to?).with(:responses).and_return(false)

      expect do
        adapter.responses_create(parameters: { model: "gpt-5-mini", input: "hello" })
      end.to raise_error(StandardError, /Responses API not supported/)
    end

    it "delegates responses_create when supported" do
      responses_resource = double("ResponsesResource") # rubocop:disable RSpec/VerifiedDoubles
      allow(raw_client).to receive(:respond_to?).with(:responses).and_return(true)
      allow(raw_client).to receive(:responses).and_return(responses_resource)
      expect(responses_resource).to receive(:create).with(parameters: { model: "gpt-5-mini", input: "hello" }).and_return("responses_result")

      expect(adapter.responses_create(parameters: { model: "gpt-5-mini", input: "hello" })).to eq("responses_result")
    end
  end

  describe "official_openai adapter contract" do
    subject(:adapter) { described_class.new(raw_client:, backend: :official_openai) }

    it "normalizes chat responses via chat.completions.create" do
      chat_resource = double("OfficialChatResource") # rubocop:disable RSpec/VerifiedDoubles
      chat_completions = double("OfficialChatCompletions") # rubocop:disable RSpec/VerifiedDoubles
      response_object = double("OfficialChatResponse", to_h: { id: "chat_1", choices: [{ message: { content: "hi" } }] }) # rubocop:disable RSpec/VerifiedDoubles

      allow(raw_client).to receive(:respond_to?).with(:chat).and_return(true)
      allow(raw_client).to receive(:chat).and_return(chat_resource)
      allow(chat_resource).to receive(:respond_to?).with(:completions).and_return(true)
      allow(chat_resource).to receive(:completions).and_return(chat_completions)
      expect(chat_completions).to receive(:create).with(model: "gpt-4.1", messages: [{ role: "user", content: "hi" }]).and_return(response_object)

      result = adapter.chat_create(parameters: { model: "gpt-4.1", messages: [{ role: "user", content: "hi" }] })

      expect(result).to eq(
        "id" => "chat_1",
        "choices" => [
          { "message" => { "content" => "hi" } }
        ]
      )
    end

    it "normalizes completion responses via completions.create" do
      completions_resource = double("OfficialCompletionsResource") # rubocop:disable RSpec/VerifiedDoubles
      response_object = double("OfficialCompletionResponse", to_h: { choices: [{ text: "hello" }] }) # rubocop:disable RSpec/VerifiedDoubles

      allow(raw_client).to receive(:respond_to?).with(:completions).and_return(true)
      allow(raw_client).to receive(:completions).and_return(completions_resource)
      expect(completions_resource).to receive(:create).with(model: "gpt-3.5-turbo-instruct", prompt: "hello").and_return(response_object)

      result = adapter.completions_create(parameters: { model: "gpt-3.5-turbo-instruct", prompt: "hello" })

      expect(result).to eq("choices" => [{ "text" => "hello" }])
    end

    it "normalizes responses API payloads via responses.create" do
      responses_resource = double("OfficialResponsesResource") # rubocop:disable RSpec/VerifiedDoubles
      response_object = double("OfficialResponsesResponse", to_h: { output: [{ type: "message" }], usage: { input_tokens: 3 } }) # rubocop:disable RSpec/VerifiedDoubles

      allow(raw_client).to receive(:respond_to?).with(:responses).and_return(true)
      allow(raw_client).to receive(:responses).and_return(responses_resource)
      expect(responses_resource).to receive(:create).with(model: "gpt-5-mini", input: "hi").and_return(response_object)

      result = adapter.responses_create(parameters: { model: "gpt-5-mini", input: "hi" })

      expect(result).to eq(
        "output" => [{ "type" => "message" }],
        "usage" => { "input_tokens" => 3 }
      )
    end

    it "normalizes embedding responses via embeddings.create" do
      embeddings_resource = double("OfficialEmbeddingsResource") # rubocop:disable RSpec/VerifiedDoubles
      response_object = double("OfficialEmbeddingsResponse", to_h: { data: [{ embedding: [0.1, 0.2, 0.3] }] }) # rubocop:disable RSpec/VerifiedDoubles

      allow(raw_client).to receive(:respond_to?).with(:embeddings).and_return(true)
      allow(raw_client).to receive(:embeddings).and_return(embeddings_resource)
      expect(embeddings_resource).to receive(:create).with(model: "text-embedding-3-small", input: "hello").and_return(response_object)

      result = adapter.embeddings_create(parameters: { model: "text-embedding-3-small", input: "hello" })

      expect(result).to eq("data" => [{ "embedding" => [0.1, 0.2, 0.3] }])
    end

    it "supports responses API when the client exposes responses" do
      allow(raw_client).to receive(:respond_to?).with(:responses).and_return(true)

      expect(adapter.supports_responses_api?).to be(true)
    end

    it "raises a clear error when chat resource is missing" do
      allow(raw_client).to receive(:respond_to?).with(:chat).and_return(false)

      expect do
        adapter.chat_create(parameters: { model: "gpt-4.1", messages: [] })
      end.to raise_error(Boxcars::ConfigurationError, /does not expose #chat/)
    end
  end
end
