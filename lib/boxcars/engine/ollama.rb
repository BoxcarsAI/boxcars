# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A engine that uses local GPT4All API.
  class Ollama < Engine
    attr_reader :prompts, :model_kwargs, :batch_size, :uri_base, :ollama_params

    # The default parameters to use when asking the engine.
    DEFAULT_PARAMS = {
      model: "llama3",
      temperature: 0.1,
      max_tokens: 4096
    }.freeze

    # the default name of the engine
    DEFAULT_NAME = "Ollama engine"
    # the default description of the engine
    DEFAULT_DESCRIPTION = "useful for when you need to use local AI to answer questions. " \
                          "You should ask targeted questions"
    # the default uri base
    DEFAULT_URI_BASE = 'http://localhost:11434'

    # A engine is a container for a single tool to run.
    # @param name [String] The name of the engine. Defaults to "OpenAI engine".
    # @param description [String] A description of the engine. Defaults to:
    #        useful for when you need to use AI to answer questions. You should ask targeted questions".
    # @param prompts [Array<String>] The prompts to use when asking the engine. Defaults to [].
    # @param batch_size [Integer] The number of prompts to send to the engine at once. Defaults to 2.
    # @param uri_base [String] The base URL for connecting to an Ollama server. Defaults to http://localhost:11434.
    def initialize(name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, prompts: [], batch_size: 2, uri_base: DEFAULT_URI_BASE, **kwargs)
      @ollama_params = DEFAULT_PARAMS.merge(kwargs)
      @prompts = prompts
      @batch_size = batch_size
      @uri_base = uri_base
      super(description: description, name: name)
    end

    # Get the OpenAI API client
    # @param groq_api_key [String] The access token to use when asking the engine.
    #   Defaults to Boxcars.configuration.groq_api_key
    #:OpenAI::Client @return [OpenAI::Client] The OpenAI API gem client.
    def open_ai_client
      ::OpenAI::Client.new uri_base: @uri_base
    end

    def conversation_model?(model)
      true
    end

    # Get an answer from the engine.
    # @param prompt [String] The prompt to use when asking the engine.
    # @param groq_api_key [String] The access token to use when asking the engine.
    #   Defaults to Boxcars.configuration.groq_api_key.
    # @param kwargs [Hash] Additional parameters to pass to the engine if wanted.
    def client(prompt:, inputs: {}, **kwargs)
      clnt   = open_ai_client
      params = ollama_params.merge(kwargs)
      prompt = prompt.first if prompt.is_a?(Array)
      if params[:model] =~ /^o/
        params.delete(:response_format)
        params.delete(:stop)
      end
      params = prompt.as_messages(inputs).merge(params)
      if Boxcars.configuration.log_prompts
        Boxcars.debug(params[:messages].last(2).map { |p| ">>>>>> Role: #{p[:role]} <<<<<<\n#{p[:content]}" }.join("\n"), :cyan)
      end
      clnt.chat(parameters: params)
    rescue StandardError => e
      err = e.respond_to?(:response) ? e.response[:body] : e
      Boxcars.warn("Ollama Error #{e.class.name}: #{err}", :red)
      raise
    end

    # get an answer from the engine for a question.
    # @param question [String] The question to ask the engine.
    # @param kwargs [Hash] Additional parameters to pass to the engine if wanted.
    def run(question, **kwargs)
      prompt = Prompt.new(template: question)
      response = client(prompt: prompt, **kwargs)
      raise Error, "Ollama: No response from API" unless response
      raise Error, "Ollama: #{response['error']}" if response["error"]

      answer = response["choices"].map { |c| c.dig("message", "content") || c["text"] }.join("\n").strip
      Boxcars.debug("Answer: #{answer}", :cyan)
      answer
    end

    def check_response(response, must_haves: %w[choices])
      if response['error']
        code = response.dig('error', 'code')
        msg = response.dig('error', 'message') || 'unknown error'

        raise ValueError, "Ollama error: #{msg}"
      end

      must_haves.each do |key|
        raise ValueError, "Expecting key #{key} in response" unless response.key?(key)
      end
    end
  end
end
