# frozen_string_literal: true

require "spec_helper"
require "boxcars/engine/groq"
require "boxcars/engine/gemini_ai"
require "boxcars/engine/ollama"

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
end
