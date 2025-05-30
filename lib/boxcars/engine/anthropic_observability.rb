# frozen_string_literal: true

require 'json'

module Boxcars
  # Module to handle observability for Anthropic API calls
  module AnthropicObservability
    private

    # Mimics IntelligenceBase#_extract_error_details_for_observability
    def _anthropic_extract_error_details(response_data:, properties:)
      error = response_data[:error]
      return unless error

      properties[:error_message] = error.message
      properties[:error_class] = error.class.name
      properties[:error_backtrace] = error.backtrace&.join("\n")

      # If the error is from Anthropic gem and has a response body or specific type
      if error.is_a?(::Anthropic::Error)
        properties[:error_type] = error.type if error.respond_to?(:type)
      # API call made but was not successful (e.g. error in response content)
      elsif !response_data[:success] && response_data[:response_obj]
        properties[:error_message] ||= response_data.dig(:response_obj, 'error', 'message') || "Anthropic API call failed"
        properties[:error_class] ||= "Boxcars::Error"
      end
    end

    # Mimics IntelligenceBase#_build_observability_properties
    def _anthropic_build_observability_properties(duration_ms:, current_params:, api_request_params:, request_context:,
                                                  response_data:)
      properties = {
        provider: :anthropic, # Hardcoded for this engine
        model_name: _anthropic_extract_model_name(current_params, api_request_params),
        prompt_content: _anthropic_extract_prompt_content(request_context),
        inputs: request_context[:inputs],
        api_call_parameters: current_params, # User-intended and default params
        duration_ms: duration_ms,
        success: response_data[:success]
      }.merge(_anthropic_extract_response_properties(response_data))

      _anthropic_extract_error_details(response_data: response_data, properties: properties)
      properties
    end

    # Mimics IntelligenceBase#_extract_model_name
    def _anthropic_extract_model_name(current_params, api_request_params)
      # Prefer model from actual API request if available, fallback to current_params
      api_request_params&.dig(:model) || current_params&.dig(:model) || DEFAULT_PARAMS[:model]
    end

    # Mimics IntelligenceBase#_extract_prompt_content
    # Adapts for how Anthropic structures messages (system prompt + messages array)
    def _anthropic_extract_prompt_content(request_context)
      content = []
      _add_system_prompt_to_content(content, request_context)
      _add_user_prompt_to_content(content, request_context)
      content.empty? ? nil : content
    end

    def _add_system_prompt_to_content(content, request_context)
      system_prompt_for_api = request_context.dig(:conversation_for_api, :system)
      return unless system_prompt_for_api && !system_prompt_for_api.to_s.strip.empty?

      content << { role: "system",
                   content: system_prompt_for_api }
    end

    def _add_user_prompt_to_content(content, request_context)
      prompt = request_context[:prompt]
      if prompt.is_a?(Boxcars::Prompt) && prompt.template && !prompt.template.to_s.strip.empty?
        content << { role: "user", content: prompt.template }
      else
        _add_fallback_user_prompt_to_content(content, request_context)
      end
    end

    def _add_fallback_user_prompt_to_content(content, request_context)
      api_messages = request_context.dig(:conversation_for_api, :messages)
      system_prompt_for_api = request_context.dig(:conversation_for_api, :system) # To avoid duplicating system message

      if api_messages.is_a?(Array) && !api_messages.empty?
        _process_api_messages(content, api_messages, system_prompt_for_api)
      elsif request_context[:prompt]
        _process_direct_prompt(content, request_context)
      end
    end

    def _process_api_messages(content, api_messages, system_prompt_for_api)
      api_messages.each do |msg|
        # Skip system messages if already added from the dedicated :system key
        next if msg[:role].to_s == "system" && system_prompt_for_api && !system_prompt_for_api.to_s.strip.empty?

        content << { role: msg[:role], content: _anthropic_extract_message_content_from_parts(msg[:content]) }
      end
    end

    def _process_direct_prompt(content, request_context)
      prompt_obj = request_context[:prompt]
      inputs = request_context[:inputs] || {}
      prompt_text = _get_prompt_text_from_object(prompt_obj, inputs)

      is_user_message_already_present = content.any? { |c| c[:role].to_s == "user" }
      content << { role: "user", content: prompt_text } unless is_user_message_already_present
    end

    def _get_prompt_text_from_object(prompt_obj, inputs)
      if prompt_obj.respond_to?(:as_prompt)
        formatted = prompt_obj.as_prompt(inputs: inputs)
        formatted.is_a?(Hash) ? formatted[:prompt] : formatted.to_s
      else
        prompt_obj.to_s
      end
    end

    # Helper for _anthropic_extract_prompt_content to handle Anthropic's content array
    def _anthropic_extract_message_content_from_parts(message_content)
      return message_content if message_content.is_a?(String)

      if message_content.is_a?(Array)
        return message_content.map do |part|
          part.is_a?(Hash) ? part[:text] || part.to_s : part.to_s
        end.join("\n")
      end

      message_content.to_s
    end

    # Mimics IntelligenceBase#_extract_response_properties
    def _anthropic_extract_response_properties(response_data)
      raw_response_body = response_data[:response_obj]
      parsed_response_body = response_data[:success] ? raw_response_body : nil
      status_code = response_data[:status_code]

      {
        response_raw_body: raw_response_body ? JSON.pretty_generate(raw_response_body) : nil,
        response_parsed_body: parsed_response_body,
        status_code: status_code
      }
    end
  end
end
