# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A engine that uses GeminiAI's API.
  class GeminiAi < Engine
    attr_reader :prompts, :llm_parmas, :model_kwargs, :batch_size

    # The default parameters to use when asking the engine.
    DEFAULT_PARAMS = {
      model: "gemini-1.5-flash-latest",
      temperature: 0.1
    }.freeze

    # the default name of the engine
    DEFAULT_NAME = "GeminiAI engine"
    # the default description of the engine
    DEFAULT_DESCRIPTION = "useful for when you need to use AI to answer questions. " \
                          "You should ask targeted questions"

    # A engine is a container for a single tool to run.
    # @param name [String] The name of the engine. Defaults to "GeminiAI engine".
    # @param description [String] A description of the engine. Defaults to:
    #        useful for when you need to use AI to answer questions. You should ask targeted questions".
    # @param prompts [Array<String>] The prompts to use when asking the engine. Defaults to [].
    # @param batch_size [Integer] The number of prompts to send to the engine at once. Defaults to 20.
    def initialize(name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, prompts: [], batch_size: 20, **kwargs)
      @llm_parmas = DEFAULT_PARAMS.merge(kwargs)
      @prompts = prompts
      @batch_size = batch_size
      super(description: description, name: name)
    end

    # Get the OpenAI API client
    # @param gemini_api_key [String] The access token to use when asking the engine.
    #   Defaults to Boxcars.configuration.gemini_api_key
    # @return [OpenAI::Client] The OpenAI API gem client.
    def self.open_ai_client(gemini_api_key: nil)
      access_token = Boxcars.configuration.gemini_api_key(gemini_api_key: gemini_api_key)
      ::OpenAI::Client.new(access_token: access_token, uri_base: "https://generativelanguage.googleapis.com/v1beta/openai/")
    end

    def conversation_model?(_model)
      true
    end

    # Get an answer from the engine.
    # @param prompt [String] The prompt to use when asking the engine.
    # @param gemini_api_key [String] The access token to use when asking the engine.
    #   Defaults to Boxcars.configuration.gemini_api_key.
    # @param kwargs [Hash] Additional parameters to pass to the engine if wanted.
    def client(prompt:, inputs: {}, gemini_api_key: nil, **kwargs)
      clnt = GeminiAi.open_ai_client(gemini_api_key: gemini_api_key)
      params = llm_parmas.merge(kwargs)
      prompt = prompt.first if prompt.is_a?(Array)
      params = prompt.as_messages(inputs).merge(params)
      if Boxcars.configuration.log_prompts
        Boxcars.debug(params[:messages].last(2).map { |p| ">>>>>> Role: #{p[:role]} <<<<<<\n#{p[:content]}" }.join("\n"), :cyan)
      end
      clnt.chat(parameters: params)
    rescue => e
      Boxcars.error(e, :red)
      raise
    end

    # get an answer from the engine for a question.
    # @param question [String] The question to ask the engine.
    # @param kwargs [Hash] Additional parameters to pass to the engine if wanted.
    def run(question, **kwargs)
      prompt = Prompt.new(template: question)
      response = client(prompt: prompt, **kwargs)
      raise Error, "GeminiAI: No response from API" unless response

      check_response(response)
      response["choices"].map { |c| c.dig("message", "content") || c["text"] }.join("\n").strip
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
    def check_response(response, must_haves: %w[choices])
      if response['error'].is_a?(Hash)
        code = response.dig('error', 'code')
        msg = response.dig('error', 'message') || 'unknown error'
        raise KeyError, "GEMINI_API_TOKEN not valid" if code == 'invalid_api_key'

        raise ValueError, "GeminiAI error: #{msg}"
      end

      must_haves.each do |key|
        raise ValueError, "Expecting key #{key} in response" unless response.key?(key)
      end
    end

    # the engine type
    def engine_type
      "gemini_ai"
    end

    # Calculate the maximum number of tokens possible to generate for a prompt.
    # @param prompt_text [String] The prompt text to use.
    # @return [Integer] the number of tokens possible to generate.
    def max_tokens_for_prompt(prompt_text)
      num_tokens = get_num_tokens(prompt_text)

      # get max context size for model by name
      max_size = 8096
      max_size - num_tokens
    end
  end
end
