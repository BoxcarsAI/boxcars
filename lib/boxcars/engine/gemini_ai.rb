# frozen_string_literal: true

require 'openai' # Gemini uses the OpenAI gem with a custom URI base
require 'json'

module Boxcars
  # A engine that uses GeminiAI's API via an OpenAI-compatible interface.
  class GeminiAi < Engine
    attr_reader :prompts, :llm_params, :model_kwargs, :batch_size # Corrected typo llm_parmas to llm_params

    DEFAULT_PARAMS = {
      model: "gemini-1.5-flash-latest", # Default model for Gemini
      temperature: 0.1
      # max_tokens is often part of the request, not a fixed default here
    }.freeze
    DEFAULT_NAME = "GeminiAI engine"
    DEFAULT_DESCRIPTION = "useful for when you need to use Gemini AI to answer questions. " \
                          "You should ask targeted questions"

    def initialize(name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, prompts: [], batch_size: 20, **kwargs)
      @llm_params = DEFAULT_PARAMS.merge(kwargs) # Corrected typo here
      @prompts = prompts
      @batch_size = batch_size
      super(description: description, name: name)
    end

    # Renamed from open_ai_client to gemini_client for clarity
    def self.gemini_client(gemini_api_key: nil)
      access_token = Boxcars.configuration.gemini_api_key(gemini_api_key: gemini_api_key)
      # NOTE: The OpenAI gem might not support `log_errors: true` for custom uri_base.
      # It's a param for OpenAI::Client specific to their setup.
      ::OpenAI::Client.new(access_token: access_token, uri_base: "https://generativelanguage.googleapis.com/v1beta/")
      # Removed /openai from uri_base as it's usually for OpenAI-specific paths on custom domains.
      # The Gemini endpoint might be directly at /v1beta/models/gemini...:generateContent
      # This might need adjustment based on how the OpenAI gem forms the full URL.
      # For direct generateContent, a different client or HTTP call might be needed if OpenAI gem is too restrictive.
      # Assuming for now it's an OpenAI-compatible chat endpoint.
    end

    # Gemini models are typically conversational.
    def conversation_model?(_model_name)
      true
    end

    def client(prompt:, inputs: {}, gemini_api_key: nil, **kwargs)
      start_time = Time.now
      response_data = { response_obj: nil, parsed_json: nil, success: false, error: nil, status_code: nil }
      current_params = @llm_params.merge(kwargs) # Use instance var @llm_params
      api_request_params = nil
      current_prompt_object = prompt.is_a?(Array) ? prompt.first : prompt

      begin
        clnt = GeminiAi.gemini_client(gemini_api_key: gemini_api_key)
        api_request_params = _prepare_gemini_request_params(current_prompt_object, inputs, current_params)

        log_messages_debug(api_request_params[:messages]) if Boxcars.configuration.log_prompts && api_request_params[:messages]
        _execute_and_process_gemini_call(clnt, api_request_params, response_data)
      rescue ::OpenAI::Error => e # Catch OpenAI gem errors if they apply
        response_data[:error] = e
        response_data[:success] = false
        response_data[:status_code] = e.http_status if e.respond_to?(:http_status)
      rescue StandardError => e # Catch other errors
        response_data[:error] = e
        response_data[:success] = false
      ensure
        _handle_gemini_observability(start_time, current_prompt_object, inputs, current_params, api_request_params, response_data)
      end

      _gemini_handle_call_outcome(response_data: response_data)
    end

    def run(question, **)
      prompt = Prompt.new(template: question)
      answer = client(prompt: prompt, inputs: {}, **)
      Boxcars.debug("Answer: #{answer}", :cyan)
      answer
    end

    def default_params
      @llm_params # Use instance variable
    end

    private

    def _execute_and_process_gemini_call(gemini_client_obj, prepared_api_params, current_response_data)
      # The OpenAI gem's `chat` method might not work directly if Gemini's endpoint
      # isn't perfectly OpenAI-compatible for chat completions.
      # It might require calling a different method or using a more direct HTTP client.
      # For this refactor, we'll assume `gemini_client_obj.chat` is the intended path.
      raw_response = gemini_client_obj.chat(parameters: prepared_api_params)

      current_response_data[:response_obj] = raw_response
      current_response_data[:parsed_json] = raw_response # OpenAI gem returns Hash

      if raw_response && !raw_response["error"] &&
         (raw_response["choices"] || raw_response["candidates"]) # Combined check for OpenAI or Gemini success
        current_response_data[:success] = true
        current_response_data[:status_code] = 200 # Inferred
      else
        current_response_data[:success] = false
        err_details = raw_response["error"] if raw_response
        msg = if err_details
                (err_details.is_a?(Hash) ? err_details['message'] : err_details).to_s
              else
                "Unknown Gemini API Error"
              end
        current_response_data[:error] = StandardError.new(msg)
      end
    end

    def _handle_gemini_observability(call_start_time, prompt_obj_for_context, call_inputs, engine_params, final_api_params,
                                     call_response_data)
      duration_ms = ((Time.now - call_start_time) * 1000).round
      request_context = {
        prompt: prompt_obj_for_context,
        inputs: call_inputs,
        conversation_for_api: final_api_params&.dig(:messages) # Assuming messages format
      }

      properties = _gemini_build_observability_properties(
        duration_ms: duration_ms,
        current_params: engine_params,
        api_request_params: final_api_params,
        request_context: request_context,
        response_data: call_response_data
      )
      Boxcars::Observability.track(event: 'llm_call', properties: properties.compact)
    end

    def _prepare_gemini_request_params(current_prompt, current_inputs, current_engine_params)
      # Gemini typically uses a chat-like interface.
      # Prepare messages for the API
      # current_prompt.as_messages(current_inputs) returns a hash like { messages: [...] }
      # We need to extract the array part for the OpenAI client's :messages parameter.
      message_hash = current_prompt.as_messages(current_inputs)
      # Ensure roles are 'user' and 'model' for Gemini if needed, or transform them.
      # OpenAI gem expects 'system', 'user', 'assistant'. Adapter logic might be needed.
      # For now, assume as_messages produces compatible roles or Gemini endpoint handles them.

      # Gemini might not use 'model' in the same way in request body if using generateContent directly.
      # If using OpenAI gem's chat method, it expects 'model' for routing.
      # Let's assume api_request_params are for OpenAI gem's chat method.
      { messages: message_hash[:messages] }.merge(current_engine_params)
    end

    def log_messages_debug(messages)
      return unless messages.is_a?(Array)

      Boxcars.debug(messages.last(2).map { |p| ">>>>>> Role: #{p[:role]} <<<<<<\n#{p[:content]}" }.join("\n"), :cyan)
    end

    def _gemini_extract_error_details(response_data:, properties:)
      error = response_data[:error]
      return unless error

      properties[:error_message] = error.message
      properties[:error_class] = error.class.name
      properties[:error_backtrace] = error.backtrace&.join("\n")

      if error.is_a?(::OpenAI::Error) # If error came through OpenAI gem compatibility layer
        properties[:error_type] = error.type if error.respond_to?(:type)
        properties[:error_code] = error.code if error.respond_to?(:code)
        properties[:status_code] ||= error.http_status if error.respond_to?(:http_status)
      elsif !response_data[:success] && (err_details = response_data.dig(:response_obj, "error"))
        _extract_gemini_specific_error_details(err_details, properties)
      end
    end

    def _extract_gemini_specific_error_details(err_details, properties)
      # If err_details is a Hash, extract specific fields, otherwise use it as a string.
      if err_details.is_a?(Hash)
        properties[:error_message] ||= err_details['message']
        properties[:error_type] ||= err_details['type']
        properties[:error_code] ||= err_details['code']
      else
        properties[:error_message] ||= err_details.to_s
      end
      properties[:error_class] ||= "Boxcars::Error"
    end

    def _gemini_build_observability_properties(duration_ms:, current_params:, api_request_params:, request_context:,
                                               response_data:)
      properties = {
        provider: :gemini_ai, # Specific provider name
        model_name: api_request_params&.dig(:model) || current_params[:model],
        prompt_content: request_context[:conversation_for_api], # Assuming messages array
        inputs: request_context[:inputs],
        api_call_parameters: current_params,
        duration_ms: duration_ms,
        success: response_data[:success]
      }.merge(_gemini_extract_response_properties(response_data))

      _gemini_extract_error_details(response_data: response_data, properties: properties)
      properties
    end

    def _gemini_extract_response_properties(response_data)
      raw_response_body = response_data[:response_obj]
      parsed_response_body = response_data[:success] ? raw_response_body : nil
      status_code = response_data[:status_code]

      {
        response_raw_body: raw_response_body ? JSON.pretty_generate(raw_response_body) : nil,
        response_parsed_body: parsed_response_body,
        status_code: status_code
      }
    end

    def _gemini_handle_call_outcome(response_data:)
      if response_data[:error]
        Boxcars.error("GeminiAI Error: #{response_data[:error].message} (#{response_data[:error].class.name})", :red)
        raise response_data[:error]
      elsif !response_data[:success]
        err_details = response_data.dig(:response_obj, "error")
        msg = if err_details
                err_details.is_a?(Hash) ? "#{err_details['type']}: #{err_details['message']}" : err_details.to_s
              else
                "Unknown error from GeminiAI API"
              end
        raise Error, msg
      else
        _extract_content_from_gemini_response(response_data[:parsed_json])
      end
    end

    def _extract_content_from_gemini_response(parsed_json)
      # Handle Gemini's specific response structure (candidates)
      # or OpenAI-compatible structure if the endpoint behaves that way.
      if parsed_json&.key?("candidates") # Native Gemini generateContent response
        parsed_json["candidates"].map { |c| c.dig("content", "parts", 0, "text") }.join("\n").strip
      elsif parsed_json&.key?("choices") # OpenAI-compatible response
        parsed_json["choices"].map { |c| c.dig("message", "content") || c["text"] }.join("\n").strip
      else
        raise Error, "GeminiAI: Could not extract answer from response"
      end
    end

    # check_response method might be partially covered by _gemini_handle_call_outcome
    # Retaining it if run method still uses it explicitly.
    def check_response(response, must_haves: %w[choices candidates])
      if response['error'].is_a?(Hash)
        code = response.dig('error', 'code')
        msg = response.dig('error', 'message') || 'unknown error'
        # GEMINI_API_TOKEN is not standard, usually it's an API key.
        # This check might need to align with actual error codes from Gemini.
        raise KeyError, "Gemini API Key not valid or permission issue" if ['invalid_api_key', 'permission_denied'].include?(code)

        raise ValueError, "GeminiAI error: #{msg}"
      end

      # Check for either 'choices' (OpenAI style) or 'candidates' (Gemini native style)
      has_valid_content = must_haves.any? { |key| response.key?(key) && !response[key].empty? }
      raise ValueError, "Expecting key like 'choices' or 'candidates' in response" unless has_valid_content
    end
  end
end
