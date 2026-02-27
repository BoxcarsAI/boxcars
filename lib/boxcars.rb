# frozen_string_literal: true

require 'logger'

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # Error class for all Boxcars errors.
  class Error < StandardError; end

  # Error class for all Boxcars configuration errors.
  class ConfigurationError < Error; end

  # Error class for all Boxcars argument errors.
  class ArgumentError < Error; end

  # Error class for all Boxcars value errors.
  class ValueError < Error; end

  # Error class for all Boxcars security errors.
  class SecurityError < Error; end

  # Error class for all Boxcars key errors.
  class KeyError < Error; end

  # Error class for all Boxcars XML errors.
  class XmlError < Error; end

  # Configuration contains gem settings
  class Configuration
    attr_writer :openai_access_token, :serpapi_api_key, :groq_api_key, :cerebras_api_key, :perplexity_api_key
    attr_accessor :organization_id, :logger, :log_prompts, :log_generated, :default_train, :default_engine, :default_model,
                  :observability_backend, :strict_deprecated_model_aliases

    def initialize
      @organization_id = nil
      @logger = Rails.logger if defined?(Rails)
      @log_prompts = ENV.fetch("LOG_PROMPTS", false)
      @log_generated = ENV.fetch("LOG_GEN", false)
      @strict_deprecated_model_aliases = false
      self.openai_official_require_native = ENV.fetch("OPENAI_OFFICIAL_REQUIRE_NATIVE", false)
    end

    def openai_official_client_builder
      @openai_official_client_builder
    end

    def openai_official_client_builder=(builder)
      unless builder.nil? || builder.respond_to?(:call)
        raise ConfigurationError, "openai_official_client_builder must be callable (Proc/lambda) or nil"
      end

      @openai_official_client_builder = builder
    end

    def openai_official_require_native
      !!@openai_official_require_native
    end

    def openai_official_require_native=(value)
      @openai_official_require_native = normalize_boolean(value, attr_name: :openai_official_require_native)
    end

    # @return [String] The OpenAI Access Token either from arg or env.
    def openai_access_token(**kwargs)
      key_lookup(:openai_access_token, kwargs)
    end

    # @return [String] The SerpAPI API key either from arg or env.
    def serpapi_api_key(**kwargs)
      key_lookup(:serpapi_api_key, kwargs)
    end

    # @return [String] The Anthropic API key either from arg or env.
    def anthropic_api_key(**kwargs)
      key_lookup(:anthropic_api_key, kwargs)
    end

    # @return [String] The Cohere API key either from arg or env.
    def cohere_api_key(**kwargs)
      key_lookup(:cohere_api_key, kwargs)
    end

    # @return [String] The Groq API key either from arg or env.
    def groq_api_key(**kwargs)
      key_lookup(:groq_api_key, kwargs)
    end

    # @return [String] The Cerebras API key either from arg or env.
    def cerebras_api_key(**kwargs)
      key_lookup(:cerebras_api_key, kwargs)
    end

    # @return [String] The Google AI API key either from arg or env.
    def gemini_api_key(**kwargs)
      key_lookup(:gemini_api_key, kwargs)
    end

    # @return [String] The Together AI API key either from arg or env.
    def together_api_key(**kwargs)
      key_lookup(:together_api_key, kwargs)
    end

    # @return [String] The Perplexity API key either from arg or env.
    def perplexity_api_key(**kwargs)
      key_lookup(:perplexity_api_key, kwargs)
    end

    private

    def normalize_boolean(value, attr_name:)
      return value if value == true || value == false

      normalized = value.to_s.strip.downcase
      return true if %w[1 true yes y on].include?(normalized)
      return false if normalized.empty? || %w[0 false no n off].include?(normalized)

      raise ConfigurationError,
            "#{attr_name} must be a boolean-like value (true/false, 1/0, yes/no)"
    end

    def check_key(key, val)
      return val unless val.nil? || val.empty?

      error_text = ":#{key} missing! Please pass key, or set #{key.to_s.upcase} environment variable."
      raise ConfigurationError, error_text
    end

    def key_lookup(key, kwargs)
      val = if kwargs.key?(key) && !kwargs[key].nil?
              # override with kwargs if present
              kwargs[key]
            elsif (provided_val = instance_variable_get("@#{key}"))
              # use saved value if present. Set using Boxcars.configuration.the_key = "abcde"
              provided_val
            else
              # otherwise, dig out of the environment
              env_keys = [key.to_s.upcase]
              env_keys << "OPENAI_API_KEY" if key == :openai_access_token
              env_val = env_keys.lazy.map { |env_key| ENV.fetch(env_key, nil) }.find { |candidate| !candidate.nil? && !candidate.empty? }
              env_val
            end
      check_key(key, val)
    end
  end

  # @return [Boxcars::Configuration] The configuration object.
  class << self
    attr_writer :configuration
  end

  def self.configuration
    @configuration ||= Boxcars::Configuration.new
  end

  # Configure the gem.
  def self.configure
    yield(configuration)
  end

  # Return the default Train class.
  def self.train
    configuration.default_train || Boxcars::ZeroShot
  end

  # Return the default Engine class.
  def self.engine
    configuration.default_engine || Boxcars::Openai
  end

  # return a proc that will ask the user for input
  def self.ask_user
    proc do |changes, _code|
      puts "This request will make #{changes} changes. Are you sure you want to run it? (y/[n])"
      answer = gets.chomp
      answer.downcase == 'y'
    end
  end

  # Return a logger, possibly if set.
  def self.logger
    Boxcars.configuration.logger
  end

  # Keep a running log of log messages
  def self.log
    @log ||= []
    @log
  end

  # Resets the log and return the old log
  def self.take_log
    logs = @log
    @log = []
    logs
  end

  # Logging system
  # debug log
  def self.debug(msg, color = nil, **)
    msg = colorize(msg.to_s, color, **) if color
    log << msg
    if logger
      logger.debug(msg)
    else
      puts msg
    end
  end

  # info log
  def self.info(msg, color = nil, **)
    msg = colorize(msg.to_s, color, **) if color
    log << msg
    if logger
      logger.info(msg)
    else
      puts msg
    end
  end

  # warn log
  def self.warn(msg, color = nil, **)
    msg = colorize(msg.to_s, color, **) if color
    log << msg
    if logger
      logger.warn(msg)
    else
      puts msg
    end
  end

  # error log
  def self.error(msg, color = nil, **)
    msg = colorize(msg.to_s, color, **) if color
    log << msg
    if logger
      logger.error(msg)
    else
      puts msg
    end
  end

  # simple colorization
  def self.colorize(str, color, **options)
    background = options[:background] || options[:bg] || false
    style = options[:style]
    offsets = %i[gray red green yellow blue magenta cyan white]
    styles = %i[normal bold dark italic underline xx xx underline xx strikethrough]
    start = background ? 40 : 30
    color_code = start + (offsets.index(color) || 8)
    style_code = styles.index(style) || 0
    "\e[#{style_code};#{color_code}m#{str}\e[0m"
  end
end

require_relative "boxcars/version"
require_relative "boxcars/observation"
require_relative "boxcars/observability_backend"
require_relative "boxcars/observability"
# If users want it, they can require 'boxcars/observability_backends/multi_backend'
require_relative "boxcars/x_node"
require_relative "boxcars/prompt"
require_relative "boxcars/conversation_prompt"
require_relative "boxcars/conversation"
require_relative "boxcars/generation"
require_relative "boxcars/ruby_repl"
require_relative "boxcars/result"
require_relative "boxcars/openai_compatible_client"
require_relative "boxcars/engine"
require_relative "boxcars/boxcar"
require_relative "boxcars/mcp"
require_relative "boxcars/train"
require_relative "boxcars/engines"
