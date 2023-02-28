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

  # simple string colorization
  class ::String
    # colorize a string
    # @param color [Symbol] The color to use.
    # @param options [Hash] The options to use.
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
    attr_accessor :organization_id, :logger, :log_prompts, :default_train, :default_engine

    def initialize
      @organization_id = nil
      @logger = Rails.logger if defined?(Rails)
      @logger ||= Logger.new($stdout)
      @log_prompts = false
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
      val = if kwargs.key?(key) && !kwargs[key].nil?
              # override with kwargs if present
              kwargs[key]
            elsif (provided_val = instance_variable_get("@#{key}"))
              # use saved value if present. Set using Boxcars::configuration.the_key = "abcde"
              provided_val
            else
              # otherwise, dig out of the environment
              env_val = ENV.fetch(key.to_s.upcase, nil)
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
end

require "boxcars/version"
require "boxcars/prompt"
require "boxcars/generation"
require "boxcars/ruby_repl"
require "boxcars/engine"
require "boxcars/boxcar"
require "boxcars/train"
