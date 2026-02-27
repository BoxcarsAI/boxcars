# frozen_string_literal: true

require "spec_helper"
require "boxcars/engine/openai"

RSpec.describe Boxcars::Openai do
  let(:adapter) { double("OpenAICompatibleClient") } # rubocop:disable RSpec/VerifiedDoubles
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

  it "ignores deprecated backend options while using the official client" do
    expect(Boxcars::OpenAICompatibleClient).to receive(:build).with(
      access_token: "token-123",
      organization_id: nil,
      log_errors: true
    ).and_return(adapter)

    expect(adapter).to receive(:chat_create) do |parameters:|
      expect(parameters).to include(:model, :messages)
      expect(parameters).not_to have_key(:openai_client_backend)
      expect(parameters).not_to have_key(:client_backend)
      chat_response
    end

    engine = described_class.new(model: "gpt-4o-mini", openai_client_backend: :official_openai)
    expect(engine.run("Say hi")).to eq("backend override answer")
  end

  it "ignores per-call deprecated backend options without mutating API params" do
    expect(Boxcars::OpenAICompatibleClient).to receive(:build).with(
      access_token: "token-123",
      organization_id: nil,
      log_errors: true
    ).and_return(adapter)

    expect(adapter).to receive(:chat_create) do |parameters:|
      expect(parameters).to include(:model, :messages)
      expect(parameters).not_to have_key(:openai_client_backend)
      expect(parameters).not_to have_key(:client_backend)
      chat_response
    end

    engine = described_class.new(model: "gpt-4o-mini")
    expect(engine.run("Say hi", openai_client_backend: :ruby_openai, client_backend: :ruby_openai)).to eq("backend override answer")
  end
end
