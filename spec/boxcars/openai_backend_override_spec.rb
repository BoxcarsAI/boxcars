# frozen_string_literal: true

require "spec_helper"
require "boxcars/engine/openai"

RSpec.describe Boxcars::Openai do
  let(:adapter) { instance_double(Boxcars::OpenAIClientAdapter) }
  let(:chat_response) do
    {
      "choices" => [
        {
          "message" => { "role" => "assistant", "content" => "backend override answer" }
        }
      ]
    }
  end

  before do
    allow(Boxcars.configuration).to receive_messages(
      openai_access_token: "token-123",
      organization_id: nil
    )
  end

  it "uses engine-level openai_client_backend override" do
    expect(Boxcars::OpenAIClientAdapter).to receive(:build).with(
      access_token: "token-123",
      organization_id: nil,
      log_errors: true,
      backend: :official_openai
    ).and_return(adapter)

    expect(adapter).to receive(:chat_create) do |parameters:|
      expect(parameters).to include(:model, :messages)
      expect(parameters).not_to have_key(:openai_client_backend)
      chat_response
    end

    engine = described_class.new(model: "gpt-4o-mini", openai_client_backend: :official_openai)
    expect(engine.run("Say hi")).to eq("backend override answer")
  end

  it "allows per-call backend override without mutating API params" do
    expect(Boxcars::OpenAIClientAdapter).to receive(:build).with(
      access_token: "token-123",
      organization_id: nil,
      log_errors: true,
      backend: :ruby_openai
    ).and_return(adapter)

    expect(adapter).to receive(:chat_create) do |parameters:|
      expect(parameters).to include(:model, :messages)
      expect(parameters).not_to have_key(:openai_client_backend)
      chat_response
    end

    engine = described_class.new(model: "gpt-4o-mini", openai_client_backend: :official_openai)
    expect(engine.run("Say hi", openai_client_backend: :ruby_openai)).to eq("backend override answer")
  end
end
