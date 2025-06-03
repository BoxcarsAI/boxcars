# frozen_string_literal: true

require "spec_helper"

RSpec.describe Boxcars::Engines do
  describe ".engine" do
    it "returns default model when no model specified" do
      allow(Boxcars::GeminiAi).to receive(:new)
      described_class.engine
      expect(Boxcars::GeminiAi).to have_received(:new).with(model: "gemini-2.5-flash-preview-05-20")
    end

    it "creates OpenAI engine for GPT models" do
      allow(Boxcars::Openai).to receive(:new)
      described_class.engine(model: "gpt-4o")
      expect(Boxcars::Openai).to have_received(:new).with(model: "gpt-4o")
    end

    it "creates OpenAI engine for o1 models" do
      allow(Boxcars::Openai).to receive(:new)
      described_class.engine(model: "o1-preview")
      expect(Boxcars::Openai).to have_received(:new).with(model: "o1-preview")
    end

    it "creates Anthropic engine for sonnet alias" do
      allow(Boxcars::Anthropic).to receive(:new)
      described_class.engine(model: "sonnet")
      expect(Boxcars::Anthropic).to have_received(:new).with(model: "claude-sonnet-4-0")
    end

    it "creates Anthropic engine for anthropic alias" do
      allow(Boxcars::Anthropic).to receive(:new)
      described_class.engine(model: "anthropic")
      expect(Boxcars::Anthropic).to have_received(:new).with(model: "claude-sonnet-4-0")
    end

    it "creates Anthropic engine for opus alias" do
      allow(Boxcars::Anthropic).to receive(:new)
      described_class.engine(model: "opus")
      expect(Boxcars::Anthropic).to have_received(:new).with(model: "claude-opus-4-0")
    end

    it "creates Anthropic engine for claude models" do
      allow(Boxcars::Anthropic).to receive(:new)
      described_class.engine(model: "claude-3-5-sonnet")
      expect(Boxcars::Anthropic).to have_received(:new).with(model: "claude-3-5-sonnet")
    end

    it "creates Groq engine for groq alias" do
      allow(Boxcars::Groq).to receive(:new)
      described_class.engine(model: "groq")
      expect(Boxcars::Groq).to have_received(:new).with(model: "llama-3.3-70b-versatile")
    end

    it "creates Groq engine for deepseek alias" do
      allow(Boxcars::Groq).to receive(:new)
      described_class.engine(model: "deepseek")
      expect(Boxcars::Groq).to have_received(:new).with(model: "deepseek-r1-distill-llama-70b")
    end

    it "creates Groq engine for mistral alias" do
      allow(Boxcars::Groq).to receive(:new)
      described_class.engine(model: "mistral")
      expect(Boxcars::Groq).to have_received(:new).with(model: "mistral-saba-24b")
    end

    it "creates Groq engine for mistral models" do
      allow(Boxcars::Groq).to receive(:new)
      described_class.engine(model: "mistral-large")
      expect(Boxcars::Groq).to have_received(:new).with(model: "mistral-large")
    end

    it "creates Groq engine for meta-llama models" do
      allow(Boxcars::Groq).to receive(:new)
      described_class.engine(model: "meta-llama/llama-3.1-8b")
      expect(Boxcars::Groq).to have_received(:new).with(model: "meta-llama/llama-3.1-8b")
    end

    it "creates Perplexityai engine for online alias" do
      allow(Boxcars::Perplexityai).to receive(:new)
      described_class.engine(model: "online")
      expect(Boxcars::Perplexityai).to have_received(:new).with(model: "sonar")
    end

    it "creates Perplexityai engine for sonar alias" do
      allow(Boxcars::Perplexityai).to receive(:new)
      described_class.engine(model: "sonar")
      expect(Boxcars::Perplexityai).to have_received(:new).with(model: "sonar")
    end

    it "creates Perplexityai engine for sonar-pro alias" do
      allow(Boxcars::Perplexityai).to receive(:new)
      described_class.engine(model: "sonar-pro")
      expect(Boxcars::Perplexityai).to have_received(:new).with(model: "sonar-pro")
    end

    it "creates Perplexityai engine for sonar models" do
      allow(Boxcars::Perplexityai).to receive(:new)
      described_class.engine(model: "llama-3.1-sonar-small-128k-online")
      expect(Boxcars::Perplexityai).to have_received(:new).with(model: "llama-3.1-sonar-small-128k-online")
    end

    it "creates GeminiAi engine for flash alias" do
      allow(Boxcars::GeminiAi).to receive(:new)
      described_class.engine(model: "flash")
      expect(Boxcars::GeminiAi).to have_received(:new).with(model: "gemini-2.5-flash-preview-05-20")
    end

    it "creates GeminiAi engine for gemini-flash alias" do
      allow(Boxcars::GeminiAi).to receive(:new)
      described_class.engine(model: "gemini-flash")
      expect(Boxcars::GeminiAi).to have_received(:new).with(model: "gemini-2.5-flash-preview-05-20")
    end

    it "creates GeminiAi engine for gemini-pro alias" do
      allow(Boxcars::GeminiAi).to receive(:new)
      described_class.engine(model: "gemini-pro")
      expect(Boxcars::GeminiAi).to have_received(:new).with(model: "gemini-2.5-pro-preview-05-06")
    end

    it "creates GeminiAi engine for gemini models" do
      allow(Boxcars::GeminiAi).to receive(:new)
      described_class.engine(model: "gemini-1.5-pro")
      expect(Boxcars::GeminiAi).to have_received(:new).with(model: "gemini-1.5-pro")
    end

    it "creates Together engine for together models" do
      allow(Boxcars::Together).to receive(:new)
      described_class.engine(model: "together-llama-3.1-8b-instruct")
      expect(Boxcars::Together).to have_received(:new).with(model: "llama-3.1-8b-instruct")
    end

    it "raises error for unknown model" do
      expect { described_class.engine(model: "unknown-model") }.to raise_error(Boxcars::ArgumentError, "Unknown model: unknown-model")
    end

    it "passes additional arguments to engine" do
      allow(Boxcars::Openai).to receive(:new)
      described_class.engine(model: "gpt-4o", temperature: 0.5, max_tokens: 100)
      expect(Boxcars::Openai).to have_received(:new).with(model: "gpt-4o", temperature: 0.5, max_tokens: 100)
    end
  end

  describe ".json_engine" do
    it "creates engine with JSON response format" do
      allow(Boxcars::Openai).to receive(:new)
      described_class.json_engine(model: "gpt-4o")
      expect(Boxcars::Openai).to have_received(:new).with(
        model: "gpt-4o",
        temperature: 0.1,
        response_format: { type: "json_object" }
      )
    end

    it "removes response_format for sonnet models" do
      allow(Boxcars::Anthropic).to receive(:new)
      described_class.json_engine(model: "sonnet")
      expect(Boxcars::Anthropic).to have_received(:new).with(
        model: "claude-sonnet-4-0",
        temperature: 0.1
      )
    end

    it "removes response_format for opus models" do
      allow(Boxcars::Anthropic).to receive(:new)
      described_class.json_engine(model: "opus")
      expect(Boxcars::Anthropic).to have_received(:new).with(
        model: "claude-opus-4-0",
        temperature: 0.1
      )
    end

    it "removes response_format for llama models" do
      allow(Boxcars::Groq).to receive(:new)
      described_class.json_engine(model: "llama-3.3-70b-versatile")
      expect(Boxcars::Groq).to have_received(:new).with(
        model: "llama-3.3-70b-versatile",
        temperature: 0.1
      )
    end

    it "merges additional options" do
      allow(Boxcars::Openai).to receive(:new)
      described_class.json_engine(model: "gpt-4o", temperature: 0.5, max_tokens: 100)
      expect(Boxcars::Openai).to have_received(:new).with(
        model: "gpt-4o",
        temperature: 0.5,
        max_tokens: 100,
        response_format: { type: "json_object" }
      )
    end
  end

  describe ".valid_answer?" do
    let(:valid_result) { Boxcars::Result.new(status: :ok, answer: "test answer") }
    let(:valid_answer) { { answer: valid_result } }
    let(:invalid_answer_no_key) { { result: valid_result } }
    let(:invalid_answer_wrong_type) { { answer: "string" } }
    let(:invalid_answer_not_hash) { "not a hash" }

    it "returns true for valid answer" do
      expect(described_class.valid_answer?(valid_answer)).to be true
    end

    it "returns false for answer without :answer key" do
      expect(described_class.valid_answer?(invalid_answer_no_key)).to be false
    end

    it "returns false for answer with wrong type" do
      expect(described_class.valid_answer?(invalid_answer_wrong_type)).to be false
    end

    it "returns false for non-hash answer" do
      expect(described_class.valid_answer?(invalid_answer_not_hash)).to be false
    end
  end
end
