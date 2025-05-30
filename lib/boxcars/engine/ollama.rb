# frozen_string_literal: true

require 'openai' # Ollama uses the OpenAI gem with a custom URI base
require 'json'

module Boxcars
  # A engine that uses a local Ollama API (OpenAI-compatible).
  class Ollama < Engine
    attr_reader :prompts, :model_kwargs, :batch_size, :ollama_params

    DEFAULT_PARAMS = {
      model: "llama3", # Default model for Ollama
      temperature: 0.1,
      max_tokens: 4096 # Check if Ollama respects this or has its own limits
    }.freeze
    DEFAULT_NAME = "Ollama engine"
    DEFAULT_DESCRIPTION = "useful for when you need to use local AI to answer questions. " \
                          "You should ask targeted questions"

    def initialize(name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, prompts: [], batch_size: 2, **kwargs)
      @ollama_params = DEFAULT_PARAMS.merge(kwargs)
      @prompts = prompts
      @batch_size = batch_size # Retain if used by other methods
      super(description: description, name: name)
    end

    # Renamed from open_ai_client to ollama_client for clarity
    # Ollama doesn't use an API key by default.
    def self.ollama_client
      # The OpenAI gem requires an access_token, even if the local service doesn't.
      # Provide a dummy one if not needed, or allow configuration if Ollama setup requires one.
      ::OpenAI::Client.new(access_token: "ollama-dummy-key", uri_base: "http://localhost:11434/v1")
      # Added /v1 to uri_base, as OpenAI-compatible endpoints often version this way.
      # Verify Ollama's actual OpenAI-compatible endpoint path.
    end

    # Ollama models are typically conversational.
    def conversation_model?(_model_name)
      true
    end

    def client(prompt:, inputs: {}, **kwargs)
      start_time = Time.now
      response_data = { response_obj: nil, parsed_json: nil, success: false, error: nil, status_code: nil }
      current_params = @ollama_params.merge(kwargs)
      current_prompt_object = prompt.is_a?(Array) ? prompt.first : prompt
      api_request_params = nil # Initialize

      begin
        clnt = Ollama.ollama_client
        api_request_params = _prepare_ollama_request_params(current_prompt_object, inputs, current_params)

        log_messages_debug(api_request_params[:messages]) if Boxcars.configuration.log_prompts && api_request_params[:messages]

        _execute_and_process_ollama_call(clnt, api_request_params, response_data)
      rescue ::OpenAI::Error => e
        _handle_openai_error_for_ollama(e, response_data)
      rescue StandardError => e
        _handle_standard_error_for_ollama(e, response_data)
      ensure
        _track_ollama_observability(start_time, current_prompt_object, inputs, api_request_params, current_params, response_data)
      end

      _ollama_handle_call_outcome(response_data: response_data)
    end

    def run(question, **)
      prompt = Prompt.new(template: question)
      answer = client(prompt: prompt, inputs: {}, **) # Pass empty inputs hash
      Boxcars.debug("Answer: #{answer}", :cyan)
      answer
    end

    def default_params
      @ollama_params
    end

    private

    # Helper methods for the client method
    def _prepare_ollama_request_params(prompt_object, inputs, current_params)
      # prompt_object.as_messages(inputs) returns a hash like { messages: [...] }
      # We need to extract the array of messages for the API call.
      actual_messages_array = prompt_object.as_messages(inputs)[:messages]
      { messages: actual_messages_array }.merge(current_params)
    end

    def _execute_and_process_ollama_call(clnt, api_request_params, response_data)
      raw_response = clnt.chat(parameters: api_request_params)
      response_data[:response_obj] = raw_response
      response_data[:parsed_json] = raw_response # OpenAI gem returns Hash

      if raw_response && !raw_response["error"] && raw_response["choices"]
        response_data[:success] = true
        response_data[:status_code] = 200 # Inferred for local success
      else
        response_data[:success] = false
        err_details = raw_response["error"] if raw_response
        msg = if err_details
                (err_details.is_a?(Hash) ? err_details['message'] : err_details).to_s
              else
                "Unknown Ollama API Error"
              end
        response_data[:error] ||= Error.new(msg) # Use ||= to not overwrite existing exception
      end
    end

    def _handle_openai_error_for_ollama(error, response_data)
      response_data[:error] = error
      response_data[:success] = false
      response_data[:status_code] = error.http_status if error.respond_to?(:http_status)
    end

    def _handle_standard_error_for_ollama(error, response_data)
      response_data[:error] = error
      response_data[:success] = false
    end

    def _track_ollama_observability(start_time, prompt_object, inputs, api_request_params, current_params, response_data)
      duration_ms = ((Time.now - start_time) * 1000).round
      request_context = {
        prompt: prompt_object,
        inputs: inputs,
        conversation_for_api: api_request_params&.dig(:messages)
      }

      properties = _ollama_build_observability_properties(
        duration_ms: duration_ms,
        current_params: current_params,
        api_request_params: api_request_params,
        request_context: request_context,
        response_data: response_data
      )
      Boxcars::Observability.track(event: 'llm_call', properties: properties.compact)
    end

    # Helper methods for _ollama_extract_error_details
    def _extract_openai_error_details_for_ollama(error, properties)
      properties[:error_type] = error.type if error.respond_to?(:type)
      properties[:error_code] = error.code if error.respond_to?(:code)
      properties[:status_code] ||= error.http_status if error.respond_to?(:http_status)
    end

    def _is_ollama_api_error_response?(response_data)
      !response_data[:success] && response_data[:response_obj] && response_data[:response_obj]["error"]
    end

    def _extract_ollama_api_error_details(err_details, properties)
      if err_details.is_a?(Hash)
        properties[:error_message] ||= err_details['message']
        # Ollama might not use 'type' or 'code' in the same way as OpenAI
        properties[:error_type] ||= err_details['type']
        properties[:error_code] ||= err_details['code']
      else
        properties[:error_message] ||= err_details.to_s
      end
      properties[:error_class] ||= "Boxcars::Error"
    end

    def log_messages_debug(messages)
      return unless messages.is_a?(Array)

      Boxcars.debug(messages.last(2).map { |p| ">>>>>> Role: #{p[:role]} <<<<<<\n#{p[:content]}" }.join("\n"), :cyan)
    end

    def _ollama_extract_error_details(response_data:, properties:)
      error = response_data[:error]
      return unless error

      properties[:error_message] = error.message
      properties[:error_class] = error.class.name
      properties[:error_backtrace] = error.backtrace&.join("\n")

      if error.is_a?(::OpenAI::Error)
        _extract_openai_error_details_for_ollama(error, properties)
      elsif _is_ollama_api_error_response?(response_data)
        err_details = response_data[:response_obj]["error"]
        _extract_ollama_api_error_details(err_details, properties)
      end
    end

    def _ollama_build_observability_properties(duration_ms:, current_params:, api_request_params:, request_context:,
                                               response_data:)
      properties = {
        provider: :ollama, # Specific provider name
        model_name: api_request_params&.dig(:model) || current_params[:model],
        prompt_content: request_context[:conversation_for_api],
        inputs: request_context[:inputs],
        api_call_parameters: current_params,
        duration_ms: duration_ms,
        success: response_data[:success]
      }.merge(_ollama_extract_response_properties(response_data))

      _ollama_extract_error_details(response_data: response_data, properties: properties)
      properties
    end

    def _ollama_extract_response_properties(response_data)
      raw_response_body = response_data[:response_obj]
      # The OpenAI gem returns a Hash, so raw_response_body is already parsed if it's not an exception object.
      # We want to record this body even if success is false, for cases where error is in the body.
      parsed_response_body = raw_response_body
      status_code = response_data[:status_code]

      {
        response_raw_body: raw_response_body ? JSON.pretty_generate(raw_response_body) : nil,
        response_parsed_body: parsed_response_body,
        status_code: status_code
        # reason_phrase is typically not applicable for local Ollama via OpenAI client.
      }
    end

    def _ollama_handle_call_outcome(response_data:)
      if response_data[:error]
        Boxcars.error("Ollama Error: #{response_data[:error].message} (#{response_data[:error].class.name})", :red)
        raise response_data[:error] # Re-raise the original error
      elsif !response_data[:success]
        # This case handles errors returned in the response body but not raised as OpenAI::Error
        err_details = response_data.dig(:response_obj, "error")
        msg = if err_details
                err_details.is_a?(Hash) ? err_details['message'] : err_details.to_s
              else
                "Unknown error from Ollama API"
              end
        raise Error, msg
      else
        # Extract answer from successful response (assuming OpenAI-like structure)
        choices = response_data.dig(:parsed_json, "choices")
        raise Error, "Ollama: No choices found in response" unless choices.is_a?(Array) && !choices.empty?

        choices.map { |c| c.dig("message", "content") }.join("\n").strip
      end
    end
  end
end
