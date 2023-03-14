# frozen_string_literal: true

require 'openai'
# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A engine that uses OpenAI's API.
  class Openai < Engine
    attr_reader :prompts, :open_ai_params, :model_kwargs, :batch_size

    # The default parameters to use when asking the engine.
    DEFAULT_PARAMS = {
      model: "gpt-3.5-turbo",
      temperature: 0.7,
      max_tokens: 512
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
      @prompts = prompts
      @batch_size = batch_size
      super(description: description, name: name)
    end

    # Get an answer from the engine.
    # @param prompt [String] The prompt to use when asking the engine.
    # @param openai_access_token [String] The access token to use when asking the engine.
    #   Defaults to Boxcars.configuration.openai_access_token.
    # @param kwargs [Hash] Additional parameters to pass to the engine if wanted.
    def client(prompt:, inputs: {}, openai_access_token: nil, **kwargs)
      access_token = Boxcars.configuration.openai_access_token(openai_access_token: openai_access_token)
      organization_id = Boxcars.configuration.organization_id
      clnt = ::OpenAI::Client.new(access_token: access_token, organization_id: organization_id)
      params = open_ai_params.merge(kwargs)
      if params[:model] == "gpt-3.5-turbo"
        prompt = prompt.first if prompt.is_a?(Array)
        params = prompt.as_messages(inputs).merge(params)
        if Boxcars.configuration.log_prompts
          Boxcars.debug(params[:messages].map { |p| "#{p[:role]}: #{p[:content]}" }.join("\n"), :cyan)
        end
        clnt.chat(parameters: params)
      else
        params = prompt.as_prompt(inputs).merge(params)
        Boxcars.debug("Prompt after formatting:\n#{params[:prompt]}", :cyan) if Boxcars.configuration.log_prompts
        clnt.completions(parameters: params)
      end
    end

    # get an answer from the engine for a question.
    # @param question [String] The question to ask the engine.
    # @param kwargs [Hash] Additional parameters to pass to the engine if wanted.
    def run(question, **kwargs)
      prompt = Prompt.new(template: question)
      response = client(prompt: prompt, **kwargs)
      answer = response["choices"].map { |c| c.dig("message", "content") || c["text"] }.join("\n").strip
      puts answer
      answer
    end

    # Build extra kwargs from additional params that were passed in.
    # @param values [Hash] The values to build extra kwargs from.
    def build_extra(values:)
      values[:model_kw_args] = @open_ai_params.merge(values)
      values
    end

    # Get the default parameters for the engine.
    def default_params
      open_ai_params
    end

    # Get generation informaton
    # @param sub_choices [Array<Hash>] The choices to get generation info for.
    # @return [Array<Generation>] The generation information.
    def generation_info(sub_choices)
      sub_choices.map do |choice|
        Generation.new(
          text: choice.dig("message", "content") || choice["text"],
          generation_info: {
            finish_reason: choice.fetch("finish_reason", nil),
            logprobs: choice.fetch("logprobs", nil)
          }
        )
      end
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

    # Call out to OpenAI's endpoint with k unique prompts.
    # @param prompts [Array<String>] The prompts to pass into the model.
    # @param inputs [Array<String>] The inputs to subsitite into the prompt.
    # @param stop [Array<String>] Optional list of stop words to use when generating.
    # @return [EngineResult] The full engine output.
    def generate(prompts:, stop: nil)
      params = {}
      params[:stop] = stop if stop
      choices = []
      token_usage = {}
      # Get the token usage from the response.
      # Includes prompt, completion, and total tokens used.
      inkeys = %w[completion_tokens prompt_tokens total_tokens].freeze
      prompts.each_slice(batch_size) do |sub_prompts|
        sub_prompts.each do |sprompts, inputs|
          response = client(prompt: sprompts, inputs: inputs, **params)
          check_response(response)
          choices.concat(response["choices"])
          keys_to_use = inkeys & response["usage"].keys
          keys_to_use.each { |key| token_usage[key] = token_usage[key].to_i + response["usage"][key] }
        end
      end

      n = params.fetch(:n, 1)
      generations = []
      prompts.each_with_index do |_prompt, i|
        sub_choices = choices[i * n, (i + 1) * n]
        generations.push(generation_info(sub_choices))
      end
      EngineResult.new(generations: generations, engine_output: { token_usage: token_usage })
    end
    # rubocop:enable Metrics/AbcSize
  end

  # the identifying parameters for the engine
  def identifying_params
    params = { model_name: model_name }
    params.merge!(default_params)
    params
  end

  # the engine type
  def engine_type
    "openai"
  end

  # calculate the number of tokens used
  def get_num_tokens(text:)
    text.split.length # TODO: hook up to token counting gem
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
