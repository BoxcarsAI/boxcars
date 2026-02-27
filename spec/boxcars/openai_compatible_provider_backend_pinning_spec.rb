# frozen_string_literal: true

require "spec_helper"
require "boxcars/engine/groq"
require "boxcars/engine/gemini_ai"
require "boxcars/engine/ollama"
require "boxcars/engine/google"
require "boxcars/engine/cerebras"
require "boxcars/engine/together"

RSpec.describe "OpenAI-compatible provider backend pinning" do
  around do |example|
    original_backend = Boxcars.configuration.openai_client_backend
    Boxcars.configuration.openai_client_backend = :official_openai
    example.run
  ensure
    Boxcars.configuration.openai_client_backend = original_backend
  end

  it "pins Groq to ruby_openai regardless of global backend" do
    allow(Boxcars.configuration).to receive(:groq_api_key).with(groq_api_key: nil).and_return("groq-key")

    expect(Boxcars::OpenAICompatibleClient).to receive(:build).with(
      access_token: "groq-key",
      uri_base: "https://api.groq.com/openai/v1",
      backend: :ruby_openai
    )

    Boxcars::Groq.groq_client
  end

  it "pins GeminiAi to ruby_openai regardless of global backend" do
    allow(Boxcars.configuration).to receive(:gemini_api_key).with(gemini_api_key: nil).and_return("gemini-key")

    expect(Boxcars::OpenAICompatibleClient).to receive(:build).with(
      access_token: "gemini-key",
      uri_base: "https://generativelanguage.googleapis.com/v1beta/",
      backend: :ruby_openai
    )

    Boxcars::GeminiAi.gemini_client
  end

  it "pins Ollama to ruby_openai regardless of global backend" do
    expect(Boxcars::OpenAICompatibleClient).to receive(:build).with(
      access_token: "ollama-dummy-key",
      uri_base: "http://localhost:11434/v1",
      backend: :ruby_openai
    )

    Boxcars::Ollama.ollama_client
  end

  it "pins Google to ruby_openai regardless of global backend" do
    allow(Boxcars.configuration).to receive(:gemini_api_key).with(gemini_api_key: nil).and_return("google-key")

    expect(Boxcars::OpenAICompatibleClient).to receive(:build).with(hash_including(
                                                                      access_token: "google-key",
                                                                      uri_base: "https://generativelanguage.googleapis.com/v1beta/",
                                                                      backend: :ruby_openai
                                                                    ))

    Boxcars::Google.open_ai_client
  end

  it "pins Cerebras to ruby_openai regardless of global backend" do
    allow(Boxcars.configuration).to receive(:cerebras_api_key).with(cerebras_api_key: nil).and_return("cerebras-key")

    expect(Boxcars::OpenAICompatibleClient).to receive(:build).with(hash_including(
                                                                      access_token: "cerebras-key",
                                                                      uri_base: "https://api.cerebras.ai/v1",
                                                                      backend: :ruby_openai
                                                                    ))

    Boxcars::Cerebras.open_ai_client
  end

  it "pins Together to ruby_openai regardless of global backend" do
    allow(Boxcars.configuration).to receive(:together_api_key).with(together_api_key: nil).and_return("together-key")

    expect(Boxcars::OpenAICompatibleClient).to receive(:build).with(hash_including(
                                                                      access_token: "together-key",
                                                                      uri_base: "https://api.together.xyz/v1",
                                                                      backend: :ruby_openai
                                                                    ))

    Boxcars::Together.open_ai_client
  end
end
