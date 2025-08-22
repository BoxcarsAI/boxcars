# frozen_string_literal: true

require 'anthropic'
# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A engine that uses OpenAI's API.
  # rubocop:disable Metrics/ClassLength
  class Anthropic < Engine
    include UnifiedObservability

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
      user_id = kwargs.delete(:user_id)
      @llm_params = DEFAULT_PARAMS.merge(kwargs)
      @prompts = prompts
      @batch_size = 20
      super(description:, name:, user_id:)
    end

    def conversation_model?(_model)
      true
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
      start_time = Time.now
      response_data = { response_obj: nil, parsed_json: nil, success: false, error: nil, status_code: nil }
      current_params = llm_params.merge(kwargs)
      current_prompt_object = prompt.is_a?(Array) ? prompt.first : prompt
      api_request_params = nil

      begin
        api_key = Boxcars.configuration.anthropic_api_key(**kwargs)
        aclient = anthropic_client(anthropic_api_key: api_key)
        api_request_params = convert_to_anthropic(current_prompt_object.as_messages(inputs).merge(current_params))

        if Boxcars.configuration.log_prompts
          if api_request_params[:messages].length < 2 && api_request_params[:system] && !api_request_params[:system].empty?
            Boxcars.debug(">>>>>> Role: system <<<<<<\n#{api_request_params[:system]}")
          end
          Boxcars.debug(api_request_params[:messages].last(2).map do |p|
            ">>>>>> Role: #{p[:role]} <<<<<<\n#{p[:content]}"
          end.join("\n"), :cyan)
        end

        raw_response = aclient.messages(parameters: api_request_params)
        _process_anthropic_response(raw_response, response_data)
      rescue StandardError => e
        _handle_anthropic_error(e, response_data)
      ensure
        call_context = {
          start_time:,
          prompt_object: current_prompt_object,
          inputs:,
          api_request_params:,
          current_params:
        }
        _track_anthropic_observability(call_context, response_data)
      end

      _anthropic_handle_call_outcome(response_data:)
    end

    # get an answer from the engine for a question.
    # @param question [String] The question to ask the engine.
    # @param kwargs [Hash] Additional parameters to pass to the engine if wanted.
    def run(question, **)
      prompt = Prompt.new(template: question)
      response = client(prompt:, **)

      raise Error, "Anthropic: No response from API" unless response
      raise Error, "Anthropic: #{response['error']}" if response['error']

      answer = response['completion']
      Boxcars.debug("Answer: #{answer}", :cyan)
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

    # validate_response! method uses the base implementation with Anthropic-specific must_haves
    def validate_response!(response, must_haves: %w[completion])
      super
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
          response = client(prompt: sprompts, inputs:, **params)
          validate_response!(response)
          choices << response
        end
      end

      n = params.fetch(:n, 1)
      generations = []
      prompts.each_with_index do |_prompt, i|
        sub_choices = choices[i * n, (i + 1) * n]
        generations.push(generation_info(sub_choices))
      end
      EngineResult.new(generations:, engine_output: { token_usage: {} })
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
    # rubocop:disable Metrics/AbcSize
    def convert_to_anthropic(params)
      params[:stop_sequences] = params.delete(:stop) if params.key?(:stop)
      params[:system] = params[:messages].shift[:content] if params.dig(:messages, 0, :role) == :system
      params[:messages].pop if params[:messages].last[:content].nil? || params[:messages].last[:content].strip.empty?
      combine_assistant(params)
    end
    # rubocop:enable Metrics/AbcSize

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

    private

    # Process the raw response from Anthropic API
    # rubocop:disable Metrics/AbcSize
    def _process_anthropic_response(raw_response, response_data)
      response_data[:response_obj] = raw_response
      response_data[:parsed_json] = raw_response # Already parsed by Anthropic gem

      if raw_response && !raw_response["error"]
        response_data[:success] = true
        response_data[:status_code] = 200 # Inferred
        # Transform response to match expected format
        raw_response['completion'] = raw_response.dig('content', 0, 'text')
        raw_response.delete('content')
      else
        response_data[:success] = false
        err_details = raw_response["error"] if raw_response
        msg = err_details ? "#{err_details['type']}: #{err_details['message']}" : "Unknown Anthropic API Error"
        response_data[:error] ||= StandardError.new(msg)
      end
    end
    # rubocop:enable Metrics/AbcSize

    # Handle errors from Anthropic API calls
    def _handle_anthropic_error(error, response_data)
      response_data[:error] = error
      response_data[:success] = false
      response_data[:status_code] = error.respond_to?(:http_status) ? error.http_status : nil
    end

    # Track observability using the unified system
    def _track_anthropic_observability(call_context, response_data)
      duration_ms = ((Time.now - call_context[:start_time]) * 1000).round
      request_context = {
        prompt: call_context[:prompt_object],
        inputs: call_context[:inputs],
        conversation_for_api: call_context[:api_request_params],
        user_id:
      }

      track_ai_generation(
        duration_ms:,
        current_params: call_context[:current_params],
        request_context:,
        response_data:,
        provider: :anthropic
      )
    end

    # Handle the final outcome of the API call
    def _anthropic_handle_call_outcome(response_data:)
      if response_data[:error]
        _handle_anthropic_error_outcome(response_data[:error])
      elsif !response_data[:success]
        _handle_anthropic_response_body_error(response_data[:response_obj])
      else
        response_data[:parsed_json] # Return the raw parsed JSON
      end
    end

    # Handle error outcomes
    def _handle_anthropic_error_outcome(error_data)
      detailed_error_message = error_data.message
      if error_data.respond_to?(:response) && error_data.response
        detailed_error_message += " - Details: #{error_data.response[:body]}"
      end
      Boxcars.error("Anthropic Error: #{detailed_error_message} (#{error_data.class.name})", :red)
      raise error_data
    end

    # Handle response body errors
    def _handle_anthropic_response_body_error(response_obj)
      err_details = response_obj&.dig("error")
      msg = err_details ? "#{err_details['type']}: #{err_details['message']}" : "Unknown error from Anthropic API"
      raise Error, msg
    end
  end
  # rubocop:enable Metrics/ClassLength
end
