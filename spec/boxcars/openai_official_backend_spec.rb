# frozen_string_literal: true

require "spec_helper"
require "boxcars/engine/openai"

RSpec.describe "Boxcars::Openai with official_openai backend" do
  let(:api_key_param) { "test_openai_api_key" }
  let(:organization_id_param) { "test_org_id" }
  let(:official_client) { double("OfficialOpenAIClient") } # rubocop:disable RSpec/VerifiedDoubles

  around do |example|
    original_backend = Boxcars.configuration.openai_client_backend
    original_builder = Boxcars::OpenAICompatibleClient.official_client_builder
    Boxcars.configuration.openai_client_backend = :official_openai
    Boxcars::OpenAICompatibleClient.official_client_builder = lambda do |access_token:, uri_base:, organization_id:, log_errors:|
      expect(access_token).to eq(api_key_param)
      expect(uri_base).to be_nil
      expect(organization_id).to eq(organization_id_param)
      expect(log_errors).to eq(true)
      official_client
    end

    example.run
  ensure
    Boxcars.configuration.openai_client_backend = original_backend
    Boxcars::OpenAICompatibleClient.official_client_builder = original_builder
  end

  before do
    allow(Boxcars.configuration).to receive_messages(
      openai_access_token: api_key_param,
      organization_id: organization_id_param
    )
  end

  it "handles chat-completions via the official adapter path" do
    chat_resource = double("OfficialChatResource") # rubocop:disable RSpec/VerifiedDoubles
    chat_completions = double("OfficialChatCompletions") # rubocop:disable RSpec/VerifiedDoubles
    response_object = double( # rubocop:disable RSpec/VerifiedDoubles
      "OfficialChatResponse",
      to_h: {
        id: "chatcmpl_123",
        choices: [
          {
            message: {
              role: "assistant",
              content: "Official SDK chat response"
            }
          }
        ]
      }
    )

    allow(official_client).to receive(:respond_to?).with(:chat).and_return(true)
    allow(official_client).to receive(:chat).and_return(chat_resource)
    allow(chat_resource).to receive(:respond_to?).with(:completions).and_return(true)
    allow(chat_resource).to receive(:completions).and_return(chat_completions)
    expect(chat_completions).to receive(:create).with(hash_including(:model, :messages)).and_return(response_object)

    engine = Boxcars::Openai.new(model: "gpt-4o-mini")
    expect(engine.run("Write a short tagline")).to eq("Official SDK chat response")
  end

  it "handles legacy completions via the official adapter path" do
    completions_resource = double("OfficialCompletionsResource") # rubocop:disable RSpec/VerifiedDoubles
    response_object = double("OfficialCompletionResponse", to_h: { choices: [{ text: "Completion answer" }] }) # rubocop:disable RSpec/VerifiedDoubles

    allow(official_client).to receive(:respond_to?).with(:completions).and_return(true)
    allow(official_client).to receive(:completions).and_return(completions_resource)
    expect(completions_resource).to receive(:create).with(hash_including(:model, :prompt)).and_return(response_object)

    engine = Boxcars::Openai.new(model: "text-davinci-003")
    expect(engine.run("Write a short tagline")).to eq("Completion answer")
  end

  it "handles Responses API payloads via the official adapter path" do
    responses_resource = double("OfficialResponsesResource") # rubocop:disable RSpec/VerifiedDoubles
    response_object = double( # rubocop:disable RSpec/VerifiedDoubles
      "OfficialResponsesResponse",
      to_h: {
        id: "resp_123",
        output: [
          {
            type: "message",
            content: [
              {
                type: "output_text",
                text: { value: "Responses answer" }
              }
            ]
          }
        ]
      }
    )

    allow(official_client).to receive(:respond_to?).with(:responses).and_return(true)
    allow(official_client).to receive(:responses).and_return(responses_resource)
    expect(responses_resource).to receive(:create).with(hash_including(:model, :input)).and_return(response_object)

    engine = Boxcars::Openai.new(model: "gpt-5-mini")
    expect(engine.run("Write a short tagline")).to eq("Responses answer")
  end
end
