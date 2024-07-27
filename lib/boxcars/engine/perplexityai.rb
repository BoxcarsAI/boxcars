# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A engine that uses OpenAI's API.
  class Perplexityai < Engine
    attr_reader :prompts, :perplexity_params, :model_kwargs, :batch_size

    # The default parameters to use when asking the engine.
    DEFAULT_PER_PARAMS = {
      model: "'llama-3-sonar-large-32k-online'",
      temperature: 0.1
    }.freeze

    # the default name of the engine
    DEFAULT_PER_NAME = "PerplexityAI engine"
    # the default description of the engine
    DEFAULT_PER_DESCRIPTION = "useful for when you need to use AI to answer questions. " \
                              "You should ask targeted questions"

    # A engine is a container for a single tool to run.
    # @param name [String] The name of the engine. Defaults to "PerplexityAI engine".
    # @param description [String] A description of the engine. Defaults to:
    #        useful for when you need to use AI to answer questions. You should ask targeted questions".
    # @param prompts [Array<String>] The prompts to use when asking the engine. Defaults to [].
    # @param batch_size [Integer] The number of prompts to send to the engine at once. Defaults to 20.
    def initialize(name: DEFAULT_PER_NAME, description: DEFAULT_PER_DESCRIPTION, prompts: [], batch_size: 20, **kwargs)
      @perplexity_params = DEFAULT_PER_PARAMS.merge(kwargs)
      @prompts = prompts
      @batch_size = batch_size
      super(description: description, name: name)
    end

    def conversation_model?(_model)
      true
    end

    def chat(parameters:)
      conn = Faraday.new(url: "https://api.perplexity.ai/chat/completions") do |faraday|
        faraday.request :json
        faraday.response :json
        faraday.response :raise_error
      end

      response = conn.post do |req|
        req.headers['Authorization'] = "Bearer #{ENV.fetch('PERPLEXITY_API_KEY')}"
        req.body = {
          model: parameters[:model],
          messages: parameters[:messages]
        }
      end

      response.body
    end

    # Get an answer from the engine.
    # @param prompt [String] The prompt to use when asking the engine.
    # @param openai_access_token [String] The access token to use when asking the engine.
    #   Defaults to Boxcars.configuration.openai_access_token.
    # @param kwargs [Hash] Additional parameters to pass to the engine if wanted.
    def client(prompt:, inputs: {}, **kwargs)
      prompt = prompt.first if prompt.is_a?(Array)
      params = prompt.as_messages(inputs).merge(default_params).merge(kwargs)
      if Boxcars.configuration.log_prompts
        Boxcars.debug(params[:messages].last(2).map { |p| ">>>>>> Role: #{p[:role]} <<<<<<\n#{p[:content]}" }.join("\n"), :cyan)
      end
      chat(parameters: params)
    end

    # get an answer from the engine for a question.
    # @param question [String] The question to ask the engine.
    # @param kwargs [Hash] Additional parameters to pass to the engine if wanted.
    def run(question, **kwargs)
      prompt = Prompt.new(template: question)
      response = client(prompt: prompt, **kwargs)
      raise Error, "PerplexityAI: No response from API" unless response
      raise Error, "PerplexityAI: #{response['error']}" if response["error"]

      answer = response["choices"].map { |c| c.dig("message", "content") || c["text"] }.join("\n").strip
      puts answer
      answer
    end

    # Get the default parameters for the engine.
    def default_params
      perplexity_params
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
        raise KeyError, "PERPLEXITY_API_KEY not valid" if code == 'invalid_api_key'

        raise ValueError, "PerplexityAI error: #{msg}"
      end

      must_haves.each do |key|
        raise ValueError, "Expecting key #{key} in response" unless response.key?(key)
      end
    end
  end

  # the engine type
  def engine_type
    "perplexityai"
  end

  # calculate the number of tokens used
  def get_num_tokens(text:)
    text.split.length # TODO: hook up to token counting gem
  end

  # Calculate the maximum number of tokens possible to generate for a prompt.
  # @param prompt_text [String] The prompt text to use.
  # @return [Integer] the number of tokens possible to generate.
  def max_tokens_for_prompt(_prompt_text)
    8096
  end
end
