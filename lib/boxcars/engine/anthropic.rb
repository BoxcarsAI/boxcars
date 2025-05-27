# frozen_string_literal: true

require 'anthropic'
require 'json' # Ensure JSON is available for parsing if needed
require_relative 'anthropic_api_formatter'
require_relative 'anthropic_observability'

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A engine that uses Anthropic's API.
  class Anthropic < Engine
    include AnthropicApiFormatter
    include AnthropicObservability # Include the new module
    attr_reader :prompts, :llm_params, :model_kwargs, :batch_size

    # The default parameters to use when asking the engine.
    DEFAULT_PARAMS = {
      model: "claude-3-5-sonnet-20240620",
      max_tokens: 4096, # Anthropic API uses "max_tokens_to_sample"
      temperature: 0.1
    }.freeze

    # the default name of the engine
    DEFAULT_NAME = "Anthropic engine"
    # the default description of the engine
    DEFAULT_DESCRIPTION = "useful for when you need to use Anthropic AI to answer questions. " \
                          "You should ask targeted questions"

    def initialize(name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, prompts: [], **kwargs)
      @llm_params = DEFAULT_PARAMS.merge(kwargs)
      @prompts = prompts # Retain if used by other methods like generate
      @batch_size = 20   # Retain if used by other methods like generate
      super(description: description, name: name) # Removed prompts and batch_size from super if Engine doesn't use them
    end

    def anthropic_client(anthropic_api_key: nil)
      ::Anthropic::Client.new(access_token: anthropic_api_key)
    end

    # Get an answer from the engine.
    def client(prompt:, inputs: {}, **kwargs)
      start_time = Time.now
      # response_data structure mirrors IntelligenceBase
      response_data = { response_obj: nil, parsed_json: nil, success: false, error: nil }
      current_params = nil
      api_request_params = nil # Parameters sent to Anthropic API

      begin
        current_params = llm_params.merge(kwargs)
        api_key = Boxcars.configuration.anthropic_api_key(**current_params.slice(:anthropic_api_key))
        aclient = anthropic_client(anthropic_api_key: api_key)

        current_prompt_object, api_request_params = _prepare_anthropic_request_params(prompt, inputs, current_params)
        log_prompt_debug(api_request_params) if Boxcars.configuration.log_prompts
        _execute_and_process_anthropic_call(aclient, api_request_params, response_data)
      rescue ::Anthropic::Error => e
        response_data[:error] = e
        response_data[:success] = false
        response_data[:status_code] = _determine_status_code_for_anthropic_error(e)
      rescue StandardError => e # Catch other Anthropic errors or general errors
        response_data[:error] = e
        response_data[:success] = false
        # Try to get status code if the error object has it (e.g. from Faraday)
        response_data[:status_code] = e.respond_to?(:response) && e.response.respond_to?(:status) ? e.response.status : nil
      ensure
        _handle_anthropic_observability(start_time, current_prompt_object, inputs, current_params, api_request_params,
                                        response_data)
      end

      _anthropic_handle_call_outcome(response_data: response_data)
    end

    # get an answer from the engine for a question.
    def run(question, **kwargs)
      prompt = Prompt.new(template: question)
      # client now returns the main content directly if successful, or raises error
      answer = client(prompt: prompt, inputs: {}, **kwargs) # Pass empty inputs hash
      Boxcars.debug("Answer: #{answer}", :cyan)
      answer
    end

    # Called by Engine#generate to check the response from the client.
    # @param response [Hash] The parsed JSON response from the Anthropic API.
    # @raise [Boxcars::Error] if the response contains an error.
    def check_response(response)
      if response.is_a?(Hash) && response["error"]
        err_details = response["error"]
        msg = err_details ? "#{err_details['type']}: #{err_details['message']}" : "Unknown Anthropic API Error in check_response"
        raise Boxcars::Error, msg
      end
      true
    end

    # Get the default parameters for the engine.
    # Retained as it's used by initialize
    def default_params
      llm_params
    end

    private

    def _handle_anthropic_observability(call_start_time, prompt_obj_for_context, call_inputs, engine_params, final_api_params,
                                        call_response_data)
      duration_ms = ((Time.now - call_start_time) * 1000).round
      request_context = {
        prompt: prompt_obj_for_context, # The Boxcars::Prompt object
        inputs: call_inputs,
        # For Anthropic, conversation_for_api is effectively final_api_params[:messages]
        # and potentially final_api_params[:system]
        conversation_for_api: {
          system: final_api_params&.dig(:system),
          messages: final_api_params&.dig(:messages)
        }.compact
      }

      # Use engine_params for api_call_parameters as it reflects user's intent + defaults
      # final_api_params is what was actually sent after transformation
      properties = _anthropic_build_observability_properties(
        duration_ms: duration_ms,
        current_params: engine_params, # Parameters before Anthropic-specific transformation
        api_request_params: final_api_params, # Parameters after transformation, sent to API
        request_context: request_context,
        response_data: call_response_data
      )
      Boxcars::Observability.track(event: 'llm_call', properties: properties)
    end

    def _execute_and_process_anthropic_call(anthropic_client_obj, prepared_api_params, current_response_data)
      raw_response = anthropic_client_obj.messages(parameters: prepared_api_params)
      current_response_data[:response_obj] = raw_response # The raw response from Anthropic gem (already a Hash)
      current_response_data[:parsed_json] = raw_response # Anthropic gem already parses JSON

      # Check for success based on Anthropic's response structure
      # Anthropic gem raises an error on failure, so if we are here, it's likely a success.
      # However, their response object might have an 'error' key for some cases.
      if raw_response && !raw_response['error'] && raw_response['type'] == 'message' && raw_response['content']
        current_response_data[:success] = true
      else
        current_response_data[:success] = false
        # If Anthropic gem doesn't raise but returns an error structure
        error_message = raw_response['error'] ? raw_response['error']['message'] : 'Unknown error'
        current_response_data[:error] = StandardError.new("Anthropic API Error: #{error_message}")
      end
    end

    def _prepare_anthropic_request_params(prompt_obj, current_inputs, current_engine_params)
      # The original prompt.as_messages(inputs) is good for creating the message structure
      # The convert_to_anthropic method handles specific Anthropic formatting.
      # We need to separate the model from other params for Anthropic call.
      anthropic_specific_params = current_engine_params.dup
      model_for_api = anthropic_specific_params.delete(:model) || DEFAULT_PARAMS[:model]

      # Map generic max_tokens to anthropic's max_tokens_to_sample
      if anthropic_specific_params.key?(:max_tokens) && !anthropic_specific_params.key?(:max_tokens_to_sample)
        anthropic_specific_params[:max_tokens_to_sample] = anthropic_specific_params.delete(:max_tokens)
      end

      # Ensure prompt is a single Prompt object
      current_prompt_obj = prompt_obj.is_a?(Array) ? prompt_obj.first : prompt_obj
      messages_for_api = current_prompt_obj.as_messages(current_inputs)

      # convert_to_anthropic expects a hash with :messages and other model params
      prepared_api_request_params = { messages: messages_for_api, model: model_for_api }.merge(anthropic_specific_params)
      # Modifies prepared_api_request_params in place
      prepared_api_request_params = convert_to_anthropic(prepared_api_request_params)

      [current_prompt_obj, prepared_api_request_params]
    end

    def _determine_status_code_for_anthropic_error(error)
      return error.status_code if error.respond_to?(:status_code)

      # Since we only have generic Anthropic::Error, return a default status code
      500
    end

    def log_prompt_debug(params)
      Boxcars.debug(">>>>>> Role: system <<<<<<\n#{params[:system]}") if params[:messages].length < 2 && params[:system].present?
      # Log last two messages, or all if fewer than two
      messages_to_log = params[:messages].last(2)
      Boxcars.debug(messages_to_log.map { |p| ">>>>>> Role: #{p[:role]} <<<<<<\n#{p[:content]}" }.join("\n"), :cyan)
    end

    # Mimics IntelligenceBase#_prepare_request_data but specific to Anthropic's direct call needs
    # This is mostly handled inline in the new client method.

    # Mimics IntelligenceBase#_execute_api_call
    # This is the core block within the new client method's `begin`.

    # Mimics IntelligenceBase#_handle_call_outcome
    def _anthropic_handle_call_outcome(response_data:)
      if response_data[:error]
        Boxcars.error("Anthropic Error: #{response_data[:error].message} (#{response_data[:error].class.name})", :red)
        raise response_data[:error]
      elsif !response_data[:success]
        # This case might be redundant if Anthropic gem always raises on error
        err_msg = response_data.dig(:response_obj, 'error', 'message') || "Unknown error from Anthropic API"
        raise Error, err_msg
      else
        # Check if this is being called from the run method by examining the call stack
        calling_method = caller_locations(1, 5).find { |loc| loc.label == 'run' }
        if calling_method
          # For the run method, extract the primary text content
          response_data.dig(:parsed_json, 'content', 0, 'text')
        else
          # For the generate method, return a response structure compatible with OpenAI format
          _convert_anthropic_to_openai_format(response_data[:parsed_json])
        end
      end
    end

    def _convert_anthropic_to_openai_format(anthropic_response)
      # Convert Anthropic response to OpenAI-compatible format for Engine#generate
      content = anthropic_response.dig('content', 0, 'text') || ''

      {
        'choices' => [
          {
            'message' => {
              'content' => content,
              'role' => 'assistant'
            },
            'finish_reason' => anthropic_response['stop_reason'] || 'stop'
          }
        ],
        'usage' => {
          'prompt_tokens' => anthropic_response.dig('usage', 'input_tokens') || 0,
          'completion_tokens' => anthropic_response.dig('usage', 'output_tokens') || 0,
          'total_tokens' => (anthropic_response.dig('usage',
                                                    'input_tokens') || 0) + (anthropic_response.dig('usage',
                                                                                                    'output_tokens') || 0)
        }
      }
    end

    # Methods like `generation_info`, `check_response`, `generate` might need review
    # if they are still intended to be used and how they interact with the new client/response.
    # For now, focusing on client and run. `generate` calls client, so it will benefit from new tracking.
    # `check_response` logic is partly in _anthropic_handle_call_outcome.
    # `generation_info` is specific to how `generate` processes choices.

    # Retaining for potential use by `generate` or similar batch processing methods.
    def default_prefixes
      { system: "Human: ", user: "Human: ", assistant: "Assistant: ", history: :history }
    end
  end
end
