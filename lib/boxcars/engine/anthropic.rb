# frozen_string_literal: true
# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # An engine that uses Anthropic's API.
  # rubocop:disable Metrics/ClassLength
  class Anthropic < Engine
    include UnifiedObservability
    include OpenAICompatibleChatHelpers

    attr_reader :llm_params

    # The default parameters to use when asking the engine.
    DEFAULT_PARAMS = {
      model: "claude-3-5-sonnet-20240620",
      max_tokens: 4096,
      temperature: 0.1
    }.freeze

    # The default name of the engine.
    DEFAULT_NAME = "Anthropic engine"
    # The default description of the engine.
    DEFAULT_DESCRIPTION = "useful for when you need to use Anthropic AI to answer questions. " \
                          "You should ask targeted questions"

    # Initializes an Anthropic engine instance.
    def initialize(name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, **kwargs)
      raise ArgumentError, "unknown keyword: :prompts" if kwargs.key?(:prompts)
      user_id = kwargs.delete(:user_id)
      @llm_params = DEFAULT_PARAMS.merge(kwargs)
      super(description:, name:, batch_size: 20, user_id:)
    end

    def anthropic_client(anthropic_api_key: nil)
      Boxcars::OptionalDependency.require!("ruby-anthropic", feature: "Boxcars::Anthropic", require_as: "anthropic")
      ::Anthropic::Client.new(access_token: anthropic_api_key)
    end

    # Calls Anthropic and returns the parsed response object.
    def client(prompt:, inputs: {}, **kwargs)
      start_time = Time.now
      response_data = { response_obj: nil, parsed_json: nil, success: false, error: nil, status_code: nil }
      current_params = llm_params.merge(kwargs)
      current_prompt_object = prompt
      api_request_params = nil

      begin
        api_key = Boxcars.configuration.anthropic_api_key(**kwargs)
        aclient = anthropic_client(anthropic_api_key: api_key)
        api_request_params = convert_to_anthropic(current_prompt_object.as_messages(inputs).merge(current_params))

        if Boxcars.configuration.log_prompts
          if api_request_params[:messages].length < 2 && api_request_params[:system] && !api_request_params[:system].empty?
            Boxcars.debug(">>>>>> Role: system <<<<<<\n#{api_request_params[:system]}")
          end
          log_messages_debug(api_request_params[:messages])
        end

        raw_response = aclient.messages(parameters: api_request_params)
        process_anthropic_response(raw_response, response_data)
      rescue StandardError => e
        handle_anthropic_error(e, response_data)
      ensure
        call_context = {
          start_time:,
          prompt_object: current_prompt_object,
          inputs:,
          api_request_params:,
          current_params:
        }
        track_anthropic_observability(call_context, response_data)
      end

      anthropic_handle_call_outcome(response_data:)
    end

    def default_params
      llm_params
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
    def process_anthropic_response(raw_response, response_data)
      normalized_response = normalize_anthropic_payload(raw_response)
      response_data[:response_obj] = raw_response
      response_data[:parsed_json] = normalized_response

      if normalized_response && !normalized_response["error"]
        response_data[:success] = true
        response_data[:status_code] = 200 # Inferred
        # Transform response to match expected format
        normalized_response["completion"] = normalized_response.dig("content", 0, "text")
        normalized_response["choices"] ||= [{ "text" => normalized_response["completion"], "finish_reason" => normalized_response["stop_reason"] }]
        if normalized_response["usage"].is_a?(Hash)
          normalized_response["usage"]["prompt_tokens"] ||= normalized_response["usage"]["input_tokens"]
          normalized_response["usage"]["completion_tokens"] ||= normalized_response["usage"]["output_tokens"]
          normalized_response["usage"]["total_tokens"] ||= normalized_response["usage"]["prompt_tokens"].to_i +
                                                           normalized_response["usage"]["completion_tokens"].to_i
        end
        normalized_response.delete("content")
      else
        response_data[:success] = false
        err_details = normalized_response["error"] if normalized_response
        msg = err_details ? "#{err_details['type']}: #{err_details['message']}" : "Unknown Anthropic API Error"
        response_data[:error] ||= StandardError.new(msg)
      end
    end
    # rubocop:enable Metrics/AbcSize

    # Handle errors from Anthropic API calls
    def handle_anthropic_error(error, response_data)
      response_data[:error] = error
      response_data[:success] = false
      response_data[:status_code] = openai_compatible_error_status_code(error)
    end

    # Track observability using the unified system
    def track_anthropic_observability(call_context, response_data)
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
    def anthropic_handle_call_outcome(response_data:)
      if response_data[:error]
        handle_anthropic_error_outcome(response_data[:error])
      elsif !response_data[:success]
        handle_anthropic_response_body_error(response_data[:response_obj])
      else
        response_data[:parsed_json] # Return the raw parsed JSON
      end
    end

    # Handle error outcomes
    def handle_anthropic_error_outcome(error_data)
      detailed_error_message = error_data.message
      if error_data.respond_to?(:response) && error_data.response
        detailed_error_message += " - Details: #{error_data.response[:body]}"
      end
      Boxcars.error("Anthropic Error: #{detailed_error_message} (#{error_data.class.name})", :red)
      raise error_data
    end

    # Handle response body errors
    def handle_anthropic_response_body_error(response_obj)
      normalized_response = normalize_anthropic_payload(response_obj)
      err_details = normalized_response&.dig("error")
      msg = err_details ? "#{err_details['type']}: #{err_details['message']}" : "Unknown error from Anthropic API"
      raise Error, msg
    end

    def normalize_anthropic_payload(payload)
      return nil unless payload.is_a?(Hash)

      normalize_generate_response(payload)
    end
  end
  # rubocop:enable Metrics/ClassLength
end
