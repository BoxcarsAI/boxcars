# frozen_string_literal: true

require "spec_helper"

RSpec.describe Boxcars::Engines do
  before do
    described_class.emit_deprecation_warnings = false
    described_class.reset_deprecation_warnings!
    Boxcars.configuration.emit_deprecation_warnings = true
    Boxcars.configuration.default_model_options = {}
  end

  after do
    described_class.emit_deprecation_warnings = true
    described_class.reset_deprecation_warnings!
    Boxcars.configuration.default_model = nil
    Boxcars.configuration.default_model_options = {}
    Boxcars.configuration.emit_deprecation_warnings = true
  end

  describe ".engine" do
    it "returns default model when no model specified" do
      allow(Boxcars::GeminiAi).to receive(:new)
      described_class.engine
      expect(Boxcars::GeminiAi).to have_received(:new).with(model: "gemini-2.5-flash")
    end

    it "creates OpenAI engine for GPT models" do
      allow(Boxcars::Openai).to receive(:new)
      described_class.engine(model: "gpt-4o")
      expect(Boxcars::Openai).to have_received(:new).with(model: "gpt-4o")
    end

    it "creates OpenAI engine for o-series models" do
      allow(Boxcars::Openai).to receive(:new)
      described_class.engine(model: "o1")
      expect(Boxcars::Openai).to have_received(:new).with(model: "o1")
    end

    it "creates Anthropic engine for sonnet alias" do
      allow(Boxcars::Anthropic).to receive(:new)
      described_class.engine(model: "sonnet")
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

    it "creates GeminiAi engine for gemini models" do
      allow(Boxcars::GeminiAi).to receive(:new)
      described_class.engine(model: "gemini-2.5-pro")
      expect(Boxcars::GeminiAi).to have_received(:new).with(model: "gemini-2.5-pro")
    end

    it "creates Together engine for together models" do
      allow(Boxcars::Together).to receive(:new)
      described_class.engine(model: "together-llama-3.1-8b-instruct")
      expect(Boxcars::Together).to have_received(:new).with(model: "llama-3.1-8b-instruct")
    end

    it "creates Cerebras engine for the explicit gpt-oss model" do
      allow(Boxcars::Cerebras).to receive(:new)
      described_class.engine(model: "gpt-oss-120b")
      expect(Boxcars::Cerebras).to have_received(:new).with(model: "gpt-oss-120b")
    end

    it "creates Together engine for the explicit Qwen model" do
      allow(Boxcars::Together).to receive(:new)
      described_class.engine(model: "Qwen/Qwen2.5-VL-72B-Instruct")
      expect(Boxcars::Together).to have_received(:new).with(model: "Qwen/Qwen2.5-VL-72B-Instruct")
    end

    %w[
      anthropic
      groq
      deepseek
      mistral
      online
      huge
      online_huge
      sonar-huge
      sonar_huge
      sonar_pro
      flash
      gemini-flash
      gemini-pro
      cerebras
      qwen
    ].each do |removed_alias|
      it "rejects the removed #{removed_alias} alias" do
        expect { described_class.engine(model: removed_alias) }
          .to raise_error(Boxcars::ArgumentError, "Unknown model: #{removed_alias}")
      end
    end

    it "raises error for unknown model" do
      expect { described_class.engine(model: "unknown-model") }.to raise_error(Boxcars::ArgumentError, "Unknown model: unknown-model")
    end

    it "passes additional arguments to engine" do
      allow(Boxcars::Openai).to receive(:new)
      described_class.engine(model: "gpt-4o", temperature: 0.5, max_tokens: 100)
      expect(Boxcars::Openai).to have_received(:new).with(model: "gpt-4o", temperature: 0.5, max_tokens: 100)
    end

    it "passes configured options to the default model" do
      Boxcars.configuration.default_model = "gpt-5.6-luna"
      Boxcars.configuration.default_model_options = { reasoning_effort: "high", temperature: 0.5 }

      allow(Boxcars::Openai).to receive(:new)
      described_class.engine
      expect(Boxcars::Openai).to have_received(:new).with(
        model: "gpt-5.6-luna",
        reasoning_effort: "high",
        temperature: 0.5
      )
    end

    it "lets call options override configured default model options" do
      Boxcars.configuration.default_model = "gpt-5.6-luna"
      Boxcars.configuration.default_model_options = { reasoning_effort: "high", temperature: 0.5 }

      allow(Boxcars::Openai).to receive(:new)
      described_class.engine(reasoning_effort: "low", temperature: 0.2)
      expect(Boxcars::Openai).to have_received(:new).with(
        model: "gpt-5.6-luna",
        reasoning_effort: "low",
        temperature: 0.2
      )
    end

    it "does not pass configured default model options to an explicit model" do
      Boxcars.configuration.default_model_options = { reasoning_effort: "high" }

      allow(Boxcars::Openai).to receive(:new)
      described_class.engine(model: "gpt-4o")
      expect(Boxcars::Openai).to have_received(:new).with(model: "gpt-4o")
    end
  end

  describe ".json_engine" do
    it "does not add response_format for explicit gpt-5 models" do
      allow(Boxcars::Openai).to receive(:new)
      described_class.json_engine(model: "gpt-5.4-mini")
      expect(Boxcars::Openai).to have_received(:new).with(
        model: "gpt-5.4-mini",
        temperature: 0.1
      )
    end

    it "does not add response_format for configured default gpt-5 models" do
      Boxcars.configuration.default_model = "gpt-5.4-mini"

      allow(Boxcars::Openai).to receive(:new)
      described_class.json_engine
      expect(Boxcars::Openai).to have_received(:new).with(
        model: "gpt-5.4-mini",
        temperature: 0.1
      )
    end

    it "still adds JSON response_format for non-blocked models" do
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

    it "removes response_format for haiku models" do
      allow(Boxcars::Anthropic).to receive(:new)
      described_class.json_engine(model: "claude-haiku-4-5")
      expect(Boxcars::Anthropic).to have_received(:new).with(
        model: "claude-haiku-4-5",
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

    it "removes response_format for sonar models" do
      allow(Boxcars::Perplexityai).to receive(:new)
      described_class.json_engine(model: "sonar")
      expect(Boxcars::Perplexityai).to have_received(:new).with(
        model: "sonar",
        temperature: 0.1
      )
    end

    it "removes response_format for sonar-pro models" do
      allow(Boxcars::Perplexityai).to receive(:new)
      described_class.json_engine(model: "sonar-pro")
      expect(Boxcars::Perplexityai).to have_received(:new).with(
        model: "sonar-pro",
        temperature: 0.1
      )
    end

    it "removes response_format for llama-sonar models" do
      allow(Boxcars::Perplexityai).to receive(:new)
      described_class.json_engine(model: "llama-3.1-sonar-small-128k-online")
      expect(Boxcars::Perplexityai).to have_received(:new).with(
        model: "llama-3.1-sonar-small-128k-online",
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

    it "passes configured options to the default JSON model" do
      Boxcars.configuration.default_model = "gpt-5.6-luna"
      Boxcars.configuration.default_model_options = { reasoning_effort: "high", max_tokens: 100 }

      allow(Boxcars::Openai).to receive(:new)
      described_class.json_engine
      expect(Boxcars::Openai).to have_received(:new).with(
        model: "gpt-5.6-luna",
        reasoning_effort: "high",
        max_tokens: 100,
        temperature: 0.1
      )
    end

    it "lets JSON call options override configured default model options" do
      Boxcars.configuration.default_model = "gpt-5.6-luna"
      Boxcars.configuration.default_model_options = { reasoning_effort: "high" }

      allow(Boxcars::Openai).to receive(:new)
      described_class.json_engine(reasoning_effort: "low")
      expect(Boxcars::Openai).to have_received(:new).with(
        model: "gpt-5.6-luna",
        reasoning_effort: "low",
        temperature: 0.1
      )
    end

    it "does not pass configured default model options to an explicit JSON model" do
      Boxcars.configuration.default_model_options = { reasoning_effort: "high" }

      allow(Boxcars::Openai).to receive(:new)
      described_class.json_engine(model: "gpt-4o")
      expect(Boxcars::Openai).to have_received(:new).with(
        model: "gpt-4o",
        temperature: 0.1,
        response_format: { type: "json_object" }
      )
    end
  end

  describe ".valid_answer?" do
    let(:valid_result) { Boxcars::Result.new(status: :ok, answer: "test answer") }

    it "returns true for a conduct-style hash containing a Result under :answer" do
      expect(described_class.valid_answer?({ answer: valid_result })).to be(true)
    end

    it "returns false when :answer is missing" do
      expect(described_class.valid_answer?({ result: valid_result })).to be(false)
    end

    it "returns false when :answer is not a Result" do
      expect(described_class.valid_answer?({ answer: "string" })).to be(false)
    end

    it "returns false for non-hash values" do
      expect(described_class.valid_answer?("not a hash")).to be(false)
    end

    it "emits one deprecation warning when warnings are enabled" do
      described_class.emit_deprecation_warnings = true
      allow(Boxcars).to receive(:warn)

      described_class.valid_answer?({ answer: valid_result })
      described_class.valid_answer?({ answer: valid_result })

      expect(Boxcars).to have_received(:warn).once
    end

    it "does not emit warnings when global deprecation warnings are disabled" do
      described_class.emit_deprecation_warnings = true
      Boxcars.configuration.emit_deprecation_warnings = false
      allow(Boxcars).to receive(:warn)

      described_class.valid_answer?({ answer: valid_result })

      expect(Boxcars).not_to have_received(:warn)
    end
  end
end
