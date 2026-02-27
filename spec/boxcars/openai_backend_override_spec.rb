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

  it "raises when deprecated backend kwargs are passed to constructor" do
    expect do
      described_class.new(model: "gpt-4o-mini", openai_client_backend: :official_openai)
    end.to raise_error(Boxcars::ConfigurationError, /openai_client_backend/)
  end

  it "raises when deprecated backend kwargs are passed to #run" do
    expect(Boxcars::OpenAICompatibleClient).not_to receive(:build)
    engine = described_class.new(model: "gpt-4o-mini")
    expect do
      engine.run("Say hi", openai_client_backend: :ruby_openai, client_backend: :ruby_openai)
    end.to raise_error(Boxcars::ConfigurationError, /openai_client_backend.*client_backend|client_backend.*openai_client_backend/)
  end
end
