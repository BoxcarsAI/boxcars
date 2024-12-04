# frozen_string_literal: true

# Boxcars - a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A engine that uses Gemini's API.
  class GeminiAi < Engine
    attr_reader :prompts, :llm_params, :model_kwargs, :batch_size

    # The default parameters to use when asking the engine.
    DEFAULT_PARAMS = {
      model: "gemini-1.5-flash-latest"
    }.freeze

    # the default name of the engine
    DEFAULT_NAME = "Google Gemini AI engine"
    # the default description of the engine
    DEFAULT_DESCRIPTION = "useful for when you need to use Google Gemini AI to answer questions. " \
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

    def chat(params, gemini_api_key)
      raise Boxcars::ConfigurationError('Google AI API key not set') if gemini_api_key.blank?

      model_string = params.delete(:model_string)
      raise Boxcars::ConfigurationError('Google AI API key not set') if model_string.blank?

      # Define the API endpoint and parameters
      api_endpoint = "https://generativelanguage.googleapis.com/v1beta/models/#{model_string}:generateContent?key=#{gemini_api_key}"

      connection = Faraday.new(api_endpoint) do |faraday|
        faraday.request :url_encoded
        faraday.headers['Content-Type'] = 'application/json'
      end

      # Make the API call
      response = connection.post { |req| req.body = params.to_json }

      JSON.parse(response.body, symbolize_names: true)
    end

    # Get an answer from the engine.
    # @param prompt [String] The prompt to use when asking the engine.
    # @param gemini_api_key [String] Optional api key to use when asking the engine.
    #   Defaults to Boxcars.configuration.gemini_api_key.
    # @param kwargs [Hash] Additional parameters to pass to the engine if wanted.
    def client(prompt:, inputs: {}, **kwargs)
      api_key = Boxcars.configuration.gemini_api_key(**kwargs)
      option_params = llm_params.merge(kwargs)
      model_string = option_params.delete(:model) || DEFAULT_PARAMS[:model]
      convo = prompt.as_messages(inputs: inputs)
      # Convert conversation to Google Gemini format
      params = to_google_gemini_format(convo[:messages], option_params)
      params[:model_string] = model_string
      Boxcars.debug("Prompt after formatting:#{params[:message]}", :cyan) if Boxcars.configuration.log_prompts
      chat(params, api_key)
    end

    # get an answer from the engine for a question.
    # @param question [String] The question to ask the engine.
    # @param kwargs [Hash] Additional parameters to pass to the engine if wanted.
    def run(question, **kwargs)
      prompt = Prompt.new(template: question)
      response = client(prompt: prompt, **kwargs)

      raise Error, "GeminiAI: No response from API" unless response
      raise Error, "GeminiAI: #{response[:error]}" if response[:error]

      answer = response[:candidates].first[:content][:parts].first[:text]
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

        raise ValueError, "Gemini error: #{msg}"
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

    def to_google_gemini_format(convo, option_params)
      instructions = convo.shift.last if convo.first && convo.first[:role] == :system
      system_instructions = instructions || "You are a helpful assistant."

      # Convert conversation history to the format expected by Google
      contents = convo.map { |message| { text: message[:content] } }

      generation_config = {}
      if option_params.length.positive?
        generation_config.merge!(option_params)
        generation_config[:stopSequences] = [generation_config.delete(:stop)] if generation_config[:stop].present?
      end

      rv = {
        system_instruction: { parts: { text: system_instructions } }, # System instructions or context
        contents: { parts: contents } # The chat messages
      }

      rv[:generationConfig] = generation_config if generation_config.length.positive?
      rv
    end

    def default_prefixes
      { system: "SYSTEM: ", user: "USER: ", assistant: "CHATBOT: ", history: :history }
    end
  end
end
