# frozen_string_literal: true

require 'json'

module Boxcars
  # Module to handle observability for the OpenAI engine.
  module OpenAIObservability
    private

    def _track_openai_observability(call_context, response_data)
      start_time = call_context[:start_time]
      prompt_object = call_context[:prompt_object]
      inputs = call_context[:inputs]
      api_request_params = call_context[:api_request_params]
      current_params = call_context[:current_params]
      is_chat_model = call_context[:is_chat_model]

      duration_ms = ((Time.now - start_time) * 1000).round
      request_context_for_build = {
        prompt: prompt_object,
        inputs: inputs,
        conversation_for_api: is_chat_model ? api_request_params&.dig(:messages) : api_request_params&.dig(:prompt)
      }

      properties = _openai_build_observability_properties(
        duration_ms: duration_ms,
        current_params: current_params,
        api_request_params: api_request_params,
        request_context: request_context_for_build,
        response_data: response_data,
        is_chat_model: is_chat_model
      )
      Boxcars::Observability.track(event: 'llm_call', properties: properties.compact)
    end

    def _extract_openai_gem_error_details(error, properties)
      properties[:error_type] = error.type if error.respond_to?(:type)
      properties[:error_code] = error.code if error.respond_to?(:code)
      properties[:error_param] = error.param if error.respond_to?(:param)
      properties[:status_code] ||= error.http_status if error.respond_to?(:http_status)
      properties[:response_raw_body] ||= error.json_body.to_json if error.respond_to?(:json_body) && error.json_body
    end

    def _extract_openai_response_error_details(response_obj, properties)
      err_details = response_obj["error"]
      properties[:error_message] ||= "#{err_details['type']}: #{err_details['message']}"
      properties[:error_type] ||= err_details['type']
      properties[:error_code] ||= err_details['code']
      properties[:error_param] ||= err_details['param']
      properties[:error_class] ||= "Boxcars::Error"
    end

    def _openai_extract_error_details(response_data:, properties:)
      error = response_data[:error]
      return unless error

      properties[:error_message] = error.message
      properties[:error_class] = error.class.name
      properties[:error_backtrace] = error.backtrace&.join("\n")

      if error.is_a?(::OpenAI::Error)
        _extract_openai_gem_error_details(error, properties)
      elsif !response_data[:success] && response_data[:response_obj] && response_data[:response_obj]["error"]
        _extract_openai_response_error_details(response_data[:response_obj], properties)
      end
    end

    def _openai_build_observability_properties(duration_ms:, current_params:, api_request_params:, request_context:,
                                               response_data:, is_chat_model:)
      properties = {
        provider: :openai,
        model_name: api_request_params&.dig(:model) || current_params[:model],
        prompt_content: if is_chat_model
                          request_context[:conversation_for_api]
                        else
                          formatted_prompt = request_context[:prompt]&.format(request_context[:inputs] || {})
                          [{ role: "user", content: formatted_prompt }]
                        end,
        inputs: request_context[:inputs],
        api_call_parameters: current_params, # User-intended and default params
        duration_ms: duration_ms,
        success: response_data[:success]
      }.merge(_openai_extract_response_properties(response_data))

      _openai_extract_error_details(response_data: response_data, properties: properties)
      properties
    end

    def _openai_extract_response_properties(response_data)
      raw_response_body = response_data[:response_obj] # This is already a Hash from OpenAI gem
      parsed_response_body = response_data[:success] ? raw_response_body : nil
      status_code = response_data[:status_code] # Captured in client from error or inferred as 200
      reason_phrase = response_data[:error].respond_to?(:http_reason) ? response_data[:error].http_reason : nil

      {
        response_raw_body: raw_response_body ? JSON.pretty_generate(raw_response_body) : nil,
        response_parsed_body: parsed_response_body,
        status_code: status_code,
        reason_phrase: reason_phrase
      }
    end
  end
end
