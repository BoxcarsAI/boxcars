# frozen_string_literal: true

require "spec_helper"
require "boxcars/engine/groq"
require "boxcars/engine/gemini_ai"
require "boxcars/engine/ollama"
require "boxcars/engine/google"
require "boxcars/engine/cerebras"
require "boxcars/engine/together"

RSpec.describe "OpenAI-compatible provider client wiring" do # rubocop:disable RSpec/DescribeClass
  it "wires Groq to the expected OpenAI-compatible endpoint" do
    allow(Boxcars.configuration).to receive(:groq_api_key).with(groq_api_key: nil).and_return("groq-key")
    allow(Boxcars::OpenAIClient).to receive(:build)

    Boxcars::Groq.provider_client

    expect(Boxcars::OpenAIClient).to have_received(:build).with(hash_including(
                                                                  access_token: "groq-key",
                                                                  uri_base: "https://api.groq.com/openai/v1"
                                                                ))
  end

  it "wires GeminiAi to the expected OpenAI-compatible endpoint" do
    allow(Boxcars.configuration).to receive(:gemini_api_key).with(gemini_api_key: nil).and_return("gemini-key")
    allow(Boxcars::OpenAIClient).to receive(:build)

    Boxcars::GeminiAi.provider_client

    expect(Boxcars::OpenAIClient).to have_received(:build).with(hash_including(
                                                                  access_token: "gemini-key",
                                                                  uri_base: "https://generativelanguage.googleapis.com/v1beta/"
                                                                ))
  end

  it "wires Ollama to the expected OpenAI-compatible endpoint" do
    allow(Boxcars::OpenAIClient).to receive(:build)

    Boxcars::Ollama.provider_client

    expect(Boxcars::OpenAIClient).to have_received(:build).with(hash_including(
                                                                  access_token: "ollama-dummy-key",
                                                                  uri_base: "http://localhost:11434/v1"
                                                                ))
  end

  it "wires Ollama to a custom endpoint when uri_base is provided" do
    allow(Boxcars::OpenAIClient).to receive(:build)

    Boxcars::Ollama.provider_client(uri_base: "http://remote-ollama:9090/v1")

    expect(Boxcars::OpenAIClient).to have_received(:build).with(hash_including(
                                                                  access_token: "ollama-dummy-key",
                                                                  uri_base: "http://remote-ollama:9090/v1"
                                                                ))
  end

  it "wires Google to the expected OpenAI-compatible endpoint" do
    allow(Boxcars.configuration).to receive(:gemini_api_key).with(gemini_api_key: nil).and_return("google-key")
    allow(Boxcars::OpenAIClient).to receive(:build)

    Boxcars::Google.provider_client

    expect(Boxcars::OpenAIClient).to have_received(:build).with(hash_including(
                                                                  access_token: "google-key",
                                                                  uri_base: "https://generativelanguage.googleapis.com/v1beta/"
                                                                ))
  end

  it "wires Cerebras to the expected OpenAI-compatible endpoint" do
    allow(Boxcars.configuration).to receive(:cerebras_api_key).with(cerebras_api_key: nil).and_return("cerebras-key")
    allow(Boxcars::OpenAIClient).to receive(:build)

    Boxcars::Cerebras.provider_client

    expect(Boxcars::OpenAIClient).to have_received(:build).with(hash_including(
                                                                  access_token: "cerebras-key",
                                                                  uri_base: "https://api.cerebras.ai/v1"
                                                                ))
  end

  it "wires Together to the expected OpenAI-compatible endpoint" do
    allow(Boxcars.configuration).to receive(:together_api_key).with(together_api_key: nil).and_return("together-key")
    allow(Boxcars::OpenAIClient).to receive(:build)

    Boxcars::Together.provider_client

    expect(Boxcars::OpenAIClient).to have_received(:build).with(hash_including(
                                                                  access_token: "together-key",
                                                                  uri_base: "https://api.together.xyz/v1"
                                                                ))
  end
end
