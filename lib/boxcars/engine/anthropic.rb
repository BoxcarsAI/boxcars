# frozen_string_literal: true

require 'anthropic'
# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A engine that uses OpenAI's API.
  class Anthropic < Engine
    attr_reader :prompts, :llm_params, :model_kwargs, :batch_size

    # The default parameters to use when asking the engine.
    DEFAULT_PARAMS = {
      model: "claude-3-5-sonnet-20240620",
      max_tokens: 4096,
      temperature: 0.1
    }.freeze

    # the default name of the engine
    DEFAULT_NAME = "Anthropic engine"
    # the default description of the engine
    DEFAULT_DESCRIPTION = "useful for when you need to use Anthropic AI to answer questions. " \
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

    def conversation_model?(model)
      @conversation_model ||= (extract_model_version(model) > 3.49)
    end

    def anthropic_client(anthropic_api_key: nil)
      ::Anthropic::Client.new(access_token: anthropic_api_key)
    end

    # Get an answer from the engine.
    # @param prompt [String] The prompt to use when asking the engine.
    # @param anthropic_api_key [String] Optional api key to use when asking the engine.
    #   Defaults to Boxcars.configuration.anthropic_api_key.
    # @param kwargs [Hash] Additional parameters to pass to the engine if wanted.
    def client(prompt:, inputs: {}, **kwargs)
      model_params = llm_params.merge(kwargs)
      api_key = Boxcars.configuration.anthropic_api_key(**kwargs)
      aclient = anthropic_client(anthropic_api_key: api_key)
      prompt = prompt.first if prompt.is_a?(Array)

      if conversation_model?(model_params[:model])
        params = convert_to_anthropic(prompt.as_messages(inputs).merge(model_params))
        if Boxcars.configuration.log_prompts
          Boxcars.debug(params[:messages].last(2).map { |p| ">>>>>> Role: #{p[:role]} <<<<<<\n#{p[:content]}" }.join("\n"), :cyan)
        end
        response = aclient.messages(parameters: params)
        response['completion'] = response.dig('content', 0, 'text')
        response.delete('content')
        response
      else
        params = prompt.as_prompt(inputs: inputs, prefixes: default_prefixes, show_roles: true).merge(model_params)
        params[:prompt] = "\n\n#{params[:prompt]}" unless params[:prompt].start_with?("\n\n")
        params[:stop_sequences] = params.delete(:stop) if params.key?(:stop)
        Boxcars.debug("Prompt after formatting:#{params[:prompt]}", :cyan) if Boxcars.configuration.log_prompts
        aclient.complete(parameters: params)
      end
    end

    # get an answer from the engine for a question.
    # @param question [String] The question to ask the engine.
    # @param kwargs [Hash] Additional parameters to pass to the engine if wanted.
    def run(question, **kwargs)
      prompt = Prompt.new(template: question)
      response = client(prompt: prompt, **kwargs)

      raise Error, "Anthropic: No response from API" unless response
      raise Error, "Anthropic: #{response['error']}" if response['error']

      answer = response['completion']
      Boxcars.debug(response, :yellow)
      answer
    end

    # Get the default parameters for the engine.
    def default_params
      llm_params
    end

    # Get generation informaton
    # @param sub_choices [Array<Hash>] The choices to get generation info for.
    # @return [Array<Generation>] The generation information.
    def generation_info(sub_choices)
      sub_choices.map do |choice|
        Generation.new(
          text: choice["completion"],
          generation_info: {
            finish_reason: choice.fetch("stop_reason", nil),
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
    def check_response(response, must_haves: %w[completion])
      if response['error']
        code = response.dig('error', 'code')
        msg = response.dig('error', 'message') || 'unknown error'
        raise KeyError, "ANTHOPIC_API_KEY not valid" if code == 'invalid_api_key'

        raise ValueError, "Anthropic error: #{msg}"
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
      # Get the token usage from the response.
      # Includes prompt, completion, and total tokens used.
      prompts.each_slice(batch_size) do |sub_prompts|
        sub_prompts.each do |sprompts, inputs|
          response = client(prompt: sprompts, inputs: inputs, **params)
          check_response(response)
          choices << response
        end
      end

      n = params.fetch(:n, 1)
      generations = []
      prompts.each_with_index do |_prompt, i|
        sub_choices = choices[i * n, (i + 1) * n]
        generations.push(generation_info(sub_choices))
      end
      EngineResult.new(generations: generations, engine_output: { token_usage: {} })
    end
    # rubocop:enable Metrics/AbcSize

    # the engine type
    def engine_type
      "claude"
    end

    # calculate the number of tokens used
    def get_num_tokens(text:)
      text.split.length # TODO: hook up to token counting gem
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

    def extract_model_version(model_string)
      # Use a regular expression to find the version number
      match = model_string.match(/claude-(\d+)(?:-(\d+))?/)

      raise ArgumentError, "No version number found in model string: #{model_string}" unless match

      major = match[1].to_i
      minor = match[2].to_i

      # Combine major and minor versions
      major + (minor.to_f / 10)
    end

    # convert generic parameters to Anthopic specific ones
    def convert_to_anthropic(params)
      params[:stop_sequences] = params.delete(:stop) if params.key?(:stop)
      params[:system] = params[:messages].shift[:content] if params.dig(:messages, 0, :role) == :system
      params[:messages].pop if params[:messages].last[:content].blank?
      combine_assistant(params)
    end

    def combine_assistant(params)
      params[:messages] = combine_assistant_entries(params[:messages])
      params[:messages].last[:content].rstrip! if params[:messages].last[:role] == :assistant
      params
    end

    # if we have multiple assistant entries in a row, we need to combine them
    def combine_assistant_entries(hashes)
      combined_hashes = []
      hashes.each do |hash|
        if combined_hashes.empty? || combined_hashes.last[:role] != :assistant || hash[:role] != :assistant
          combined_hashes << hash
        else
          combined_hashes.last[:content].concat("\n", hash[:content].rstrip)
        end
      end
      combined_hashes
    end

    def default_prefixes
      { system: "Human: ", user: "Human: ", assistant: "Assistant: ", history: :history }
    end
  end
end
