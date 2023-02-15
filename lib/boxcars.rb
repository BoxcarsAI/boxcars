# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # Error class for all Boxcars errors.
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class ArgumentError < Error; end
  class ValueError < Error; end

  # simple string colorization
  class ::String
    def colorize(color, options = {})
      background = options[:background] || options[:bg] || false
      style = options[:style]
      offsets = %i[gray red green yellow blue magenta cyan white]
      styles = %i[normal bold dark italic underline xx xx underline xx strikethrough]
      start = background ? 40 : 30
      color_code = start + (offsets.index(color) || 8)
      style_code = styles.index(style) || 0
      "\e[#{style_code};#{color_code}m#{self}\e[0m"
    end
  end

  # Configuration contains gem settings
  class Configuration
    attr_writer :openai_access_token, :serpapi_api_key
    attr_accessor :organization_id, :logger

    def initialize
      @organization_id = nil
      @logger = Rails.logger if defined?(Rails)
      @logger ||= Logger.new($stdout)
    end

    # @return [String] The OpenAI Access Token either from arg or env.
    def openai_access_token(**kwargs)
      key_lookup(:openai_access_token, kwargs)
    end

    # @return [String] The SerpAPI API key either from arg or env.
    def serpapi_api_key(**kwargs)
      key_lookup(:serpapi_api_key, kwargs)
    end

    private

    def check_key(key, val)
      return val unless val.nil? || val.empty?

      error_text = ":#{key} missing! Please pass key, or set #{key.to_s.upcase} environment variable."
      raise ConfigurationError, error_text
    end

    def key_lookup(key, kwargs)
      rv = if kwargs.key?(key) && kwargs[key] != "not set"
             # override with kwargs if present
             kwargs[key]
           elsif (set_val = instance_variable_get("@#{key}"))
             # use saved value if present
             set_val
           else
             # otherwise, dig out of the environment
             new_key = ENV.fetch(key.to_s.upcase, nil)
             send("#{key}=", new_key) if new_key
             new_key
           end
      check_key(key, rv)
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
end

require "boxcars/version"
require "boxcars/llm_prompt"
require "boxcars/generation"
require "boxcars/ruby_repl"
require "boxcars/llm"
require "boxcars/boxcar"
require "boxcars/conductor"
