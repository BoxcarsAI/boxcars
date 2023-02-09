# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A LLM that uses OpenAI's API.
  class LLMOpenAI < LLM
    attr_reader :prompt_templates, :callback_manager, :verbose, :open_ai_params, :model_kwargs, :batch_size,
                :open_ai_key

    DEFAULT_PARAMS = {
      model: "text-davinci-003",
      temperature: 0.7,
      max_tokens: 256
    }.freeze

    def initialize(callback_manager: nil, prompt_templates: [], verbose: false, **kwargs)
      @open_ai_params = DEFAULT_PARAMS.merge(kwargs)
      @prompt_templates = prompt_templates
      @callback_manager = callback_manager
      @verbose = verbose
      @batch_size = kwargs[:batch_size] || 20
      super(description: "useful for when you need to use AI to answer questions." \
                         "You should ask targeted questions")
    end

    def client(prompt:, **kwargs)
      access_token = Boxcars.configuration.openai_access_token(**kwargs)
      organization_id = Boxcars.configuration.organization_id
      clnt = ::OpenAI::Client.new(access_token: access_token, organization_id: organization_id)
      the_params = { prompt: prompt }.merge(open_ai_params)
      response = clnt.completions(parameters: the_params)
      ans = response["choices"].map { |c| c["text"] }.join("\n")
      puts ans if verbose
      response
    end

    # Build extra kwargs from additional params that were passed in.
    def build_extra(values:)
      values[:model_kw_args] = @open_ai_params.merge(values)
      values
    end

    def default_params
      open_ai_params
    end

    def generation_info(sub_choices)
      sub_choices.map do |choice|
        Generation.new(
          text: choice["text"],
          generation_info: {
            finish_reason: choice.fetch("finish_reason", nil),
            logprobs: choice.fetch("logprobs", nil)
          }
        )
      end
    end

    # Call out to OpenAI's endpoint with k unique prompts.

    #   Args:
    #     prompts: The prompts to pass into the model.
    #     stop: Optional list of stop words to use when generating.

    #   Returns:
    #     The full LLM output.

    #   Example:
    #     .. code-block:: ruby

    #       response = openai.generate(["Tell me a joke."])
    # rubocop:disable Metrics/MethodLength
    # rubocop:disable Metrics/AbcSize
    def generate(prompts:, stop: nil)
      params = default_params
      params = params.merge(stop: stop) if stop
      choices = []
      token_usage = {}
      # Get the token usage from the response.
      # Includes prompt, completion, and total tokens used.
      inkeys = %w[completion_tokens prompt_tokens total_tokens].freeze
      sub_prompts = prompts.each_slice(batch_size).to_a
      sub_prompts.each do |sprompts|
        response = client(prompt: sprompts)
        choices.concat(response["choices"])
        keys_to_use = inkeys & response["usage"].keys
        keys_to_use.each { |key| token_usage[key] = token_usage[key].to_i + response["usage"][key] }
      end

      n = params.fetch(:n, 1)
      generations = []
      prompts.each_with_index do |_prompt, i|
        sub_choices = choices[i * n, (i + 1) * n]
        generations.push(generation_info(sub_choices))
      end
      LLMResult.new(generations: generations, llm_output: { token_usage: token_usage })
    end
    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/MethodLength
  end

  def identifying_params
    params = { model_name: model_name }
    params.merge!(default_params)
    params
  end

  def llm_type
    "openai"
  end

  # calculate the number of tokens used
  def get_num_tokens(text:)
    text.split.length
  end

  def modelname_to_contextsize(modelname)
    model_lookup = {
      'text-davinci-003': 4097,
      'text-curie-001': 2048,
      'text-babbage-001': 2048,
      'text-ada-001': 2048,
      'code-davinci-002': 8000,
      'code-cushman-001': 2048
    }.freeze
    model_lookup[modelname] || 4097
  end

  # Calculate the maximum number of tokens possible to generate for a prompt.

  #   Args:
  #     prompt: The prompt to use.

  #   Returns:
  #     The maximum number of tokens possible to generate for a prompt.
  def max_tokens_for_prompt(prompt)
    num_tokens = get_num_tokens(prompt)

    # get max context size for model by name
    max_size = modelname_to_contextsize(model_name)
    max_size - num_tokens
  end

  private

  def foo
    # Build the prompt
    prompt = build_prompt(prompts: prompts, stop: stop)

    # Build the kwargs
    kwargs = build_extra(values: kwargs)

    # Make the request
    response = make_request(prompt: prompt, **kwargs)

    # Parse the response
    parse_response(response: response, **kwargs)
  end
end
