# frozen_string_literal: true

module Boxcars
  # Shared helpers for engines that speak OpenAI-compatible chat APIs.
  module OpenAICompatibleChatHelpers
    private

    def prepare_openai_compatible_chat_request(prompt_object, inputs, current_params)
      { messages: prompt_object.as_messages(inputs)[:messages] }.merge(current_params)
    end

    def execute_openai_compatible_chat_call(client:, api_request_params:, response_data:, success_check:,
                                            unknown_error_message:, error_class: StandardError,
                                            preserve_existing_error: true)
      raw_response = client.chat_create(parameters: api_request_params)
      normalized_response = normalize_openai_compatible_payload(raw_response)
      response_data[:response_obj] = raw_response
      response_data[:parsed_json] = raw_response

      if normalized_response.is_a?(Hash) && !normalized_response[:error] && success_check.call(normalized_response)
        response_data[:success] = true
        response_data[:status_code] = 200
        return
      end

      response_data[:success] = false
      err_details = normalized_response[:error] if normalized_response.is_a?(Hash)
      message = if err_details
                  (err_details.is_a?(Hash) ? err_details[:message] : err_details).to_s
                else
                  unknown_error_message
                end

      response_error = error_class.new(message)
      if preserve_existing_error
        response_data[:error] ||= response_error
      else
        response_data[:error] = response_error
      end
    end

    def handle_openai_compatible_standard_error(error, response_data)
      response_data[:error] = error
      response_data[:success] = false
      response_data[:status_code] = openai_compatible_error_status_code(error)
    end

    def openai_compatible_error_status_code(error)
      return error.http_status if error.respond_to?(:http_status) && error.http_status
      return error.status if error.respond_to?(:status) && error.status
      if error.respond_to?(:response) && error.response.is_a?(Hash)
        response_status = normalize_openai_compatible_payload(error.response)[:status]
        return response_status if response_status
      end

      500
    end

    def log_messages_debug(messages)
      return unless messages.is_a?(Array)

      Boxcars.debug(messages.last(2).map { |p| ">>>>>> Role: #{p[:role]} <<<<<<\n#{p[:content]}" }.join("\n"), :cyan)
    end

    def normalize_openai_compatible_payload(payload)
      case payload
      when Hash
        payload.each_with_object({}) do |(key, value), normalized|
          normalized_key = key.is_a?(String) || key.is_a?(Symbol) ? key.to_sym : key
          normalized[normalized_key] = normalize_openai_compatible_payload(value)
        end
      when Array
        payload.map { |item| normalize_openai_compatible_payload(item) }
      else
        payload
      end
    end
  end
end
