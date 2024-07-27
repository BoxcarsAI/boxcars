# frozen_string_literal: true

# Boxcars - a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A engine that uses Cohere's API.
  class Cohere < Engine
    attr_reader :prompts, :llm_params, :model_kwargs, :batch_size

    # The default parameters to use when asking the engine.
    DEFAULT_PARAMS = {
      model: "command-r-plus",
      max_tokens: 4000,
      max_input_tokens: 1000,
      temperature: 0.2
    }.freeze

    # the default name of the engine
    DEFAULT_NAME = "Cohere engine"
    # the default description of the engine
    DEFAULT_DESCRIPTION = "useful for when you need to use Cohere AI to answer questions. " \
                          "You should ask targeted questions"

    # A engine is the driver for a single tool to run.
    # @param name [String] The name of the engine. Defaults to "OpenAI engine".
    # @param description [String] A description of the engine. Defaults to:
    #        useful for when you need to use AI to answer questions. You should ask targeted questions".
    # @param prompts [Array<String>] The prompts to use when asking the engine. Defaults to [].
    def initialize(name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, prompts: [], **kwargs)
      @llm_params = DEFAULT_PARAMS.merge(kwargs)
      @prompts = prompts
      @batch_size = 20
      super(description: description, name: name)
    end

    def conversation_model?(_model)
      true
    end

    def chat(params, cohere_api_key)
      raise Boxcars::ConfigurationError('Cohere API key not set') if cohere_api_key.blank?

      # Define the API endpoint and parameters
      api_endpoint = 'https://api.cohere.ai/v1/chat'

      connection = Faraday.new(api_endpoint) do |faraday|
        faraday.request :url_encoded
        faraday.headers['Authorization'] = "Bearer #{cohere_api_key}"
        faraday.headers['Content-Type'] = 'application/json'
      end

      # Make the API call
      response = connection.post { |req| req.body = params.to_json }

      # response_data = JSON.parse(response.body, symbolize_names: true)
      # response_data[:text]
      JSON.parse(response.body, symbolize_names: true)
    end

    # Get an answer from the engine.
    # @param prompt [String] The prompt to use when asking the engine.
    # @param cohere_api_key [String] Optional api key to use when asking the engine.
    #   Defaults to Boxcars.configuration.cohere_api_key.
    # @param kwargs [Hash] Additional parameters to pass to the engine if wanted.
    def client(prompt:, inputs: {}, **kwargs)
      api_key = Boxcars.configuration.cohere_api_key(**kwargs)
      params = prompt.as_prompt(inputs: inputs, prefixes: default_prefixes, show_roles: true).merge(llm_params.merge(kwargs))
      params[:message] = params.delete(:prompt)
      params[:stop_sequences] = params.delete(:stop) if params.key?(:stop)
      Boxcars.debug("Prompt after formatting:#{params[:message]}", :cyan) if Boxcars.configuration.log_prompts
      chat(params, api_key)
    end

    # get an answer from the engine for a question.
    # @param question [String] The question to ask the engine.
    # @param kwargs [Hash] Additional parameters to pass to the engine if wanted.
    def run(question, **kwargs)
      prompt = Prompt.new(template: question)
      response = client(prompt: prompt, **kwargs)

      raise Error, "Cohere: No response from API" unless response
      raise Error, "Cohere: #{response[:error]}" if response[:error]

      answer = response[:text]
      Boxcars.debug(response, :yellow)
      answer
    end

    # Get the default parameters for the engine.
    def default_params
      llm_params
    end

    # make sure we got a valid response
    # @param response [Hash] The response to check.
    # @param must_haves [Array<String>] The keys that must be in the response. Defaults to %w[choices].
    # @raise [KeyError] if there is an issue with the access token.
    # @raise [ValueError] if the response is not valid.
    def check_response(response, must_haves: %w[completion])
      if response['error']
        code = response.dig('error', 'code')
        msg = response.dig('error', 'message') || 'unknown error'
        raise KeyError, "ANTHOPIC_API_KEY not valid" if code == 'invalid_api_key'

        raise ValueError, "Cohere error: #{msg}"
      end

      must_haves.each do |key|
        raise ValueError, "Expecting key #{key} in response" unless response.key?(key)
      end
    end

    # the engine type
    def engine_type
      "claude"
    end

    # lookup the context size for a model by name
    # @param modelname [String] The name of the model to lookup.
    def modelname_to_contextsize(_modelname)
      100000
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

    def default_prefixes
      { system: "SYSTEM: ", user: "USER: ", assistant: "CHATBOT: ", history: :history }
    end
  end
end
