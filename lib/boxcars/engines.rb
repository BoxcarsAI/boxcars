# frozen_string_literal: true

module Boxcars
  # Factory class for creating engine instances based on model names
  # Provides convenient shortcuts and aliases for different AI models
  class Engines
    VALID_ANSWER_REMOVE_IN = "3.0"
    DEFAULT_MODEL = "gemini-2.5-flash"

    @emit_deprecation_warnings = true
    @warned_valid_answer = false

    class << self
      attr_accessor :emit_deprecation_warnings
    end

    # Create an engine instance based on the model name
    # @param model [String] The model name or alias
    # @param kw_args [Hash] Additional arguments to pass to the engine
    # @return [Boxcars::Engine] An instance of the appropriate engine class
    def self.engine(model: nil, **kw_args)
      kw_args = Boxcars.configuration.default_model_options.merge(kw_args) if model.nil?
      model ||= Boxcars.configuration.default_model || DEFAULT_MODEL
      Boxcars.logger&.info { "running api with #{model}" }

      case model.to_s
      when "gpt-oss-120b"
        Boxcars::Cerebras.new(model:, **kw_args)
      when /^(gpt-|o\d($|-))/
        Boxcars::Openai.new(model:, **kw_args)
      when "sonnet"
        Boxcars::Anthropic.new(model: "claude-sonnet-5", **kw_args)
      when "opus"
        Boxcars::Anthropic.new(model: "claude-opus-5", **kw_args)
      when /claude-/
        Boxcars::Anthropic.new(model:, **kw_args)
      when "llama-3.3-70b-versatile"
        Boxcars::Groq.new(model: "llama-3.3-70b-versatile", **kw_args)
      when /^mistral-/, %r{^meta-llama/}, /^deepseek-/
        Boxcars::Groq.new(model:, **kw_args)
      when "sonar"
        Boxcars::Perplexityai.new(model: "sonar", **kw_args)
      when "sonar-pro"
        Boxcars::Perplexityai.new(model: "sonar-pro", **kw_args)
      when /^gemini-(?!flash$|pro$)/
        Boxcars::GeminiAi.new(model:, **kw_args)
      when /-sonar-/
        Boxcars::Perplexityai.new(model:, **kw_args)
      when /^together-/
        Boxcars::Together.new(model: model[9..-1], **kw_args)
      when "Qwen/Qwen2.5-VL-72B-Instruct"
        Boxcars::Together.new(model:, **kw_args)
      else
        raise Boxcars::ArgumentError, "Unknown model: #{model}"
      end
    end

    # Create an engine instance optimized for JSON responses
    # @param model [String] The model name or alias
    # @param kw_args [Hash] Additional arguments to pass to the engine
    # @return [Boxcars::Engine] An instance of the appropriate engine class
    def self.json_engine(model: nil, **kw_args)
      default_options = { temperature: 0.1 }
      effective_model = model || Boxcars.configuration.default_model || DEFAULT_MODEL
      name = effective_model.to_s
      blocked = name.start_with?("gpt-5", "llama", "claude-") || name.match?(/sonnet|opus|haiku|sonar/)
      default_options[:response_format] = { type: "json_object" } unless blocked
      options = default_options.merge(kw_args)
      engine(model:, **options)
    end

    # Deprecated. Validate the shape returned by `Boxcar#conduct`.
    # @param answer [Object] Conduct return value.
    # @return [Boolean] True when answer is a hash containing a Boxcars::Result under :answer.
    # @deprecated Use `Boxcars::Result.valid_conduct_payload?` or `Boxcars::Result.extract`.
    def self.valid_answer?(answer)
      unless @warned_valid_answer || !deprecation_warnings_enabled?
        Boxcars.warn(
          "Boxcars::Engines.valid_answer? is deprecated; use Boxcars::Result.valid_conduct_payload? " \
          "or Boxcars::Result.extract (planned removal in v#{VALID_ANSWER_REMOVE_IN})"
        )
        @warned_valid_answer = true
      end
      Boxcars::Result.valid_conduct_payload?(answer)
    end

    def self.reset_deprecation_warnings!
      @warned_valid_answer = false
    end

    def self.deprecation_warnings_enabled?
      emit_deprecation_warnings && Boxcars.configuration.emit_deprecation_warnings
    end
  end
end
