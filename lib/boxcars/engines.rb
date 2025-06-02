# frozen_string_literal: true

module Boxcars
  # Factory class for creating engine instances based on model names
  # Provides convenient shortcuts and aliases for different AI models
  class Engines
    DEFAULT_MODEL = "gemini-2.5-flash-preview-05-20"

    # Create an engine instance based on the model name
    # @param model [String] The model name or alias
    # @param kw_args [Hash] Additional arguments to pass to the engine
    # @return [Boxcars::Engine] An instance of the appropriate engine class
    def self.engine(model: nil, **kw_args)
      model ||= Boxcars.configuration.default_model || DEFAULT_MODEL
      Boxcars.logger&.info { "running api with #{model}" }

      case model.to_s
      when /^(gpt|o\d)-/
        Boxcars::Openai.new(model:, **kw_args)
      when "anthropic", "sonnet"
        Boxcars::Anthropic.new(model: "claude-sonnet-4-0", **kw_args)
      when "opus", "claude-opus-4-0"
        Boxcars::Anthropic.new(model: "claude-opus-4-0", **kw_args)
      when /claude-/
        Boxcars::Anthropic.new(model:, **kw_args)
      when "groq", "llama-3.3-70b-versatile"
        Boxcars::Groq.new(model: "llama-3.3-70b-versatile", **kw_args)
      when "deepseek"
        Boxcars::Groq.new(model: "deepseek-r1-distill-llama-70b", **kw_args)
      when "mistral"
        Boxcars::Groq.new(model: "mistral-saba-24b", **kw_args)
      when /^mistral-/, %r{^meta-llama/}, /^deepseek-/
        Boxcars::Groq.new(model:, **kw_args)
      when "online", "sonar"
        Boxcars::Perplexityai.new(model: "sonar", **kw_args)
      when "huge", "online_huge", "sonar-huge", "sonar-pro", "sonar_pro"
        Boxcars::Perplexityai.new(model: "sonar-pro", **kw_args)
      when "flash", "gemini-flash"
        Boxcars::GeminiAi.new(model: "gemini-2.5-flash-preview-05-20", **kw_args)
      when "gemini-pro"
        Boxcars::GeminiAi.new(model: "gemini-2.5-pro-preview-05-06", **kw_args)
      when /gemini-/
        Boxcars::GeminiAi.new(model:, **kw_args)
      when /-sonar-/
        Boxcars::Perplexityai.new(model:, **kw_args)
      when /^together-/
        Boxcars::Together.new(model: model[9..-1], **kw_args)
      when "cerebras"
        Boxcars::Cerebras.new(model: "llama-3.3-70b", **kw_args)
      when "qwen"
        Boxcars::Together.new(model: "Qwen/QwQ-32B", **kw_args)
      else
        raise Boxcars::ArgumentError, "Unknown model: #{model}"
      end
    end

    # Create an engine instance optimized for JSON responses
    # @param model [String] The model name or alias
    # @param kw_args [Hash] Additional arguments to pass to the engine
    # @return [Boxcars::Engine] An instance of the appropriate engine class
    def self.json_engine(model: nil, **kw_args)
      options = { temperature: 0.1, response_format: { type: "json_object" } }.merge(kw_args)
      options.delete(:response_format) if model.to_s =~ /sonnet|opus/ || model.to_s.start_with?("llama")
      engine(model:, **options)
    end

    # Validate that an answer has the expected structure
    # @param answer [Hash] The answer to validate
    # @return [Boolean] True if the answer is valid
    def self.valid_answer?(answer)
      answer.is_a?(Hash) && answer.key?(:answer) && answer[:answer].is_a?(Boxcars::Result)
    end
  end
end
