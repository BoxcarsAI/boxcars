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
      response_data[:response_obj] = raw_response
      response_data[:parsed_json] = raw_response

      if raw_response && !raw_response["error"] && success_check.call(raw_response)
        response_data[:success] = true
        response_data[:status_code] = 200
        return
      end

      response_data[:success] = false
      err_details = raw_response["error"] if raw_response
      message = if err_details
                  (err_details.is_a?(Hash) ? err_details["message"] : err_details).to_s
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
        response_status = error.response[:status] || error.response["status"]
        return response_status if response_status
      end

      500
    end

    def log_messages_debug(messages)
      return unless messages.is_a?(Array)

      Boxcars.debug(messages.last(2).map { |p| ">>>>>> Role: #{p[:role]} <<<<<<\n#{p[:content]}" }.join("\n"), :cyan)
    end
  end
end
