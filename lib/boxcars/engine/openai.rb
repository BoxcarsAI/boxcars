# frozen_string_literal: true

require 'openai'
# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A engine that uses OpenAI's API.
  class Openai < Engine
    attr_reader :prompts, :open_ai_params, :model_kwargs, :batch_size

    # The default parameters to use when asking the engine.
    DEFAULT_PARAMS = {
      model: "gpt-4o-mini",
      temperature: 0.1,
      max_tokens: 4096
    }.freeze

    # the default name of the engine
    DEFAULT_NAME = "OpenAI engine"
    # the default description of the engine
    DEFAULT_DESCRIPTION = "useful for when you need to use AI to answer questions. " \
                          "You should ask targeted questions"

    # A engine is a container for a single tool to run.
    # @param name [String] The name of the engine. Defaults to "OpenAI engine".
    # @param description [String] A description of the engine. Defaults to:
    #        useful for when you need to use AI to answer questions. You should ask targeted questions".
    # @param prompts [Array<String>] The prompts to use when asking the engine. Defaults to [].
    # @param batch_size [Integer] The number of prompts to send to the engine at once. Defaults to 20.
    def initialize(name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, prompts: [], batch_size: 20, **kwargs)
      @open_ai_params = DEFAULT_PARAMS.merge(kwargs)
      if @open_ai_params[:model] =~ /^o/ && @open_ai_params[:max_tokens].present?
        @open_ai_params[:max_completion_tokens] = @open_ai_params.delete(:max_tokens)
        @open_ai_params.delete(:temperature)
      end

      @prompts = prompts
      @batch_size = batch_size
      super(description: description, name: name)
    end

    # Get the OpenAI API client
    # @param openai_access_token [String] The access token to use when asking the engine.
    #   Defaults to Boxcars.configuration.openai_access_token.
    # @return [OpenAI::Client] The OpenAI API client.
    def self.open_ai_client(openai_access_token: nil)
      access_token = Boxcars.configuration.openai_access_token(openai_access_token: openai_access_token)
      organization_id = Boxcars.configuration.organization_id
      ::OpenAI::Client.new(access_token: access_token, organization_id: organization_id, log_errors: true)
    end

    def conversation_model?(model)
      !!(model =~ /(^gpt-4)|(-turbo\b)|(^o\d)/)
    end

    # Get an answer from the engine.
    # @param prompt [String] The prompt to use when asking the engine.
    # @param openai_access_token [String] The access token to use when asking the engine.
    #   Defaults to Boxcars.configuration.openai_access_token.
    # @param kwargs [Hash] Additional parameters to pass to the engine if wanted.
    def client(prompt:, inputs: {}, openai_access_token: nil, **kwargs)
      clnt = Openai.open_ai_client(openai_access_token: openai_access_token)
      params = open_ai_params.merge(kwargs)
      if conversation_model?(params[:model])
        prompt = prompt.first if prompt.is_a?(Array)
        if params[:model] =~ /^o/
          params.delete(:response_format)
          params.delete(:stop)
        end
        params = get_params(prompt, inputs, params)
        clnt.chat(parameters: params)
      else
        params = prompt.as_prompt(inputs: inputs).merge(params)
        Boxcars.debug("Prompt after formatting:\n#{params[:prompt]}", :cyan) if Boxcars.configuration.log_prompts
        clnt.completions(parameters: params)
      end
    rescue StandardError => e
      err = e.respond_to?(:response) ? e.response[:body] : e
      Boxcars.warn("OpenAI Error #{e.class.name}: #{err}", :red)
      raise
    end

    # get an answer from the engine for a question.
    # @param question [String] The question to ask the engine.
    # @param kwargs [Hash] Additional parameters to pass to the engine if wanted.
    def run(question, **kwargs)
      prompt = Prompt.new(template: question)
      response = client(prompt: prompt, **kwargs)
      raise Error, "OpenAI: No response from API" unless response
      raise Error, "OpenAI: #{response['error']}" if response["error"]

      answer = response["choices"].map { |c| c.dig("message", "content") || c["text"] }.join("\n").strip
      Boxcars.debug("Answer: #{answer}", :cyan)
      answer
    end

    # Get the default parameters for the engine.
    def default_params
      open_ai_params
    end

    # make sure we got a valid response
    # @param response [Hash] The response to check.
    # @param must_haves [Array<String>] The keys that must be in the response. Defaults to %w[choices].
    # @raise [KeyError] if there is an issue with the access token.
    # @raise [ValueError] if the response is not valid.
    def check_response(response, must_haves: %w[choices])
      if response['error']
        code = response.dig('error', 'code')
        msg = response.dig('error', 'message') || 'unknown error'
        raise KeyError, "OPENAI_ACCESS_TOKEN not valid" if code == 'invalid_api_key'

        raise ValueError, "OpenAI error: #{msg}"
      end

      must_haves.each do |key|
        raise ValueError, "Expecting key #{key} in response" unless response.key?(key)
      end
    end

    def get_params(prompt, inputs, params)
      params = prompt.as_messages(inputs).merge(params)
      # Handle models like o1-mini that don't support the system role
      params[:messages].first[:role] = :user if params[:model] =~ /^o/ && params[:messages].first&.fetch(:role) == :system
      if Boxcars.configuration.log_prompts
        Boxcars.debug(params[:messages].last(2).map { |p| ">>>>>> Role: #{p[:role]} <<<<<<\n#{p[:content]}" }.join("\n"), :cyan)
      end
      params
    end
  end

  # the engine type
  def engine_type
    "openai"
  end

  # lookup the context size for a model by name
  # @param modelname [String] The name of the model to lookup.
  def modelname_to_contextsize(modelname)
    model_lookup = {
      'text-davinci-003': 4097,
      'text-curie-001': 2048,
      'text-babbage-001': 2048,
      'text-ada-001': 2048,
      'code-davinci-002': 8000,
      'code-cushman-001': 2048,
      'gpt-3.5-turbo-1': 4096
    }.freeze
    model_lookup[modelname] || 4097
  end

  # Calculate the maximum number of tokens possible to generate for a prompt.
  # @param prompt_text [String] The prompt text to use.
  # @return [Integer] the number of tokens possible to generate.
  def max_tokens_for_prompt(prompt_text)
    num_tokens = get_num_tokens(prompt_text)

    # get max context size for model by name
    max_size = modelname_to_contextsize(model_name)
    max_size - num_tokens
  end
end
