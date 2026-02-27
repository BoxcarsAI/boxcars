# frozen_string_literal: true

module Boxcars
  # Factory class for creating engine instances based on model names
  # Provides convenient shortcuts and aliases for different AI models
  class Engines
    DEFAULT_MODEL = "gemini-2.5-flash"
    DEPRECATED_MODEL_ALIASES = {
      # Generic provider aliases are convenient but ambiguous and make pruning harder.
      "anthropic" => { replacement: "sonnet", remove_in: "3.0", reason: "generic provider alias" },
      "groq" => { replacement: "llama-3.3-70b-versatile", remove_in: "3.0", reason: "generic provider alias" },
      "deepseek" => { replacement: "deepseek-r1-distill-llama-70b", remove_in: "3.0", reason: "provider-specific shortcut alias" },
      "mistral" => { replacement: "mistral-saba-24b", remove_in: "3.0", reason: "provider-specific shortcut alias" },
      "online" => { replacement: "sonar", remove_in: "3.0", reason: "ambiguous alias" },
      "huge" => { replacement: "sonar-pro", remove_in: "3.0", reason: "ambiguous alias" },
      "online_huge" => { replacement: "sonar-pro", remove_in: "3.0", reason: "ambiguous alias" },
      "sonar-huge" => { replacement: "sonar-pro", remove_in: "3.0", reason: "legacy alias spelling" },
      "sonar_huge" => { replacement: "sonar-pro", remove_in: "3.0", reason: "legacy alias spelling" },
      "sonar_pro" => { replacement: "sonar-pro", remove_in: "3.0", reason: "legacy alias spelling" },
      "flash" => { replacement: "gemini-2.5-flash", remove_in: "3.0", reason: "generic alias" },
      "gemini-flash" => { replacement: "gemini-2.5-flash", remove_in: "3.0", reason: "generic alias" },
      "gemini-pro" => { replacement: "gemini-2.5-pro", remove_in: "3.0", reason: "generic alias" },
      "cerebras" => { replacement: "gpt-oss-120b", remove_in: "3.0", reason: "generic provider alias" },
      "qwen" => { replacement: "Qwen/Qwen2.5-VL-72B-Instruct", remove_in: "3.0", reason: "provider-specific shortcut alias" }
    }.freeze

    @emit_deprecation_warnings = true
    @strict_deprecated_aliases = false
    @warned_aliases = {}

    class << self
      attr_accessor :emit_deprecation_warnings, :strict_deprecated_aliases
    end

    # Create an engine instance based on the model name
    # @param model [String] The model name or alias
    # @param kw_args [Hash] Additional arguments to pass to the engine
    # @return [Boxcars::Engine] An instance of the appropriate engine class
    def self.engine(model: nil, **kw_args)
      model ||= Boxcars.configuration.default_model || DEFAULT_MODEL
      emit_alias_deprecation_warning(model)
      Boxcars.logger&.info { "running api with #{model}" }

      case model.to_s
      when /^(gpt-|o\d($|-))/
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
      when "huge", "online_huge", "sonar-huge", "sonar_huge", "sonar-pro", "sonar_pro"
        Boxcars::Perplexityai.new(model: "sonar-pro", **kw_args)
      when "flash", "gemini-flash"
        Boxcars::GeminiAi.new(model: "gemini-2.5-flash", **kw_args)
      when "gemini-pro"
        Boxcars::GeminiAi.new(model: "gemini-2.5-pro", **kw_args)
      when /gemini-/
        Boxcars::GeminiAi.new(model:, **kw_args)
      when /-sonar-/
        Boxcars::Perplexityai.new(model:, **kw_args)
      when /^together-/
        Boxcars::Together.new(model: model[9..-1], **kw_args)
      when "cerebras"
        Boxcars::Cerebras.new(model: "gpt-oss-120b", **kw_args)
      when "qwen"
        Boxcars::Together.new(model: "Qwen/Qwen2.5-VL-72B-Instruct", **kw_args)
      else
        raise Boxcars::ArgumentError, "Unknown model: #{model}"
      end
    end

    def self.deprecated_alias_info(model)
      DEPRECATED_MODEL_ALIASES[model.to_s]
    end

    def self.deprecated_alias?(model)
      !deprecated_alias_info(model).nil?
    end

    # Create an engine instance optimized for JSON responses
    # @param model [String] The model name or alias
    # @param kw_args [Hash] Additional arguments to pass to the engine
    # @return [Boxcars::Engine] An instance of the appropriate engine class
    def self.json_engine(model: nil, **kw_args)
      default_options = { temperature: 0.1 }
      name = model.to_s
      blocked = name.start_with?("gpt-5", "llama") || name.match?(/sonnet|opus|sonar/)
      default_options[:response_format] = { type: "json_object" } unless blocked
      options = default_options.merge(kw_args)
      engine(model:, **options)
    end

    # Validate that an answer has the expected structure
    # @param answer [Hash] The answer to validate
    # @return [Boolean] True if the answer is valid
    def self.valid_answer?(answer)
      answer.is_a?(Hash) && answer.key?(:answer) && answer[:answer].is_a?(Boxcars::Result)
    end

    def self.emit_alias_deprecation_warning(model)
      model_name = model.to_s
      info = deprecated_alias_info(model_name)
      return unless info

      replacement = info[:replacement]
      remove_in = info[:remove_in]
      reason = info[:reason]
      message = "Deprecated model alias #{model_name.inspect} (#{reason}); use #{replacement.inspect} instead"
      message += " (planned removal in v#{remove_in})" if remove_in

      if strict_deprecated_aliases_enabled?
        raise Boxcars::ArgumentError, "#{message}. Set an explicit model name."
      end

      return unless emit_deprecation_warnings
      return if @warned_aliases[model_name]

      if Boxcars.logger
        Boxcars.logger.warn(message)
      else
        warn(message)
      end

      @warned_aliases[model_name] = true
    end

    def self.reset_deprecation_warnings!
      @warned_aliases = {}
    end

    def self.strict_deprecated_aliases_enabled?
      strict_deprecated_aliases || Boxcars.configuration.strict_deprecated_model_aliases
    end
  end
end
