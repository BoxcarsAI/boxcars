# frozen_string_literal: true

require 'json'
require 'securerandom'

module Boxcars
  # Module to handle observability for the OpenAI engine.
  module OpenAIObservability
    private

    def _track_openai_observability(call_context, response_data)
      duration_ms = ((Time.now - call_context[:start_time]) * 1000).round
      is_chat_model = call_context[:is_chat_model]
      api_request_params = call_context[:api_request_params] || {}
      request_context = {
        prompt: call_context[:prompt_object],
        inputs: call_context[:inputs],
        conversation_for_api: is_chat_model ? api_request_params[:messages] : api_request_params[:prompt]
      }

      properties = _openai_build_observability_properties(
        duration_ms: duration_ms,
        current_params: call_context[:current_params],
        api_request_params:,
        request_context:,
        response_data:,
        is_chat_model:
      ).compact
      # Use PostHog's standard event name for AI generation tracking
      Boxcars::Observability.track(event: '$ai_generation', properties:)
    end

    def _extract_error_message(response_data)
      if response_data[:error]
        response_data[:error].message
      elsif response_data[:response_obj] && response_data[:response_obj]["error"]
        err = response_data[:response_obj]["error"]
        "#{err['type']}: #{err['message']}"
      else
        "Unknown error"
      end
    end

    def _openai_build_observability_properties(duration_ms:, current_params:, api_request_params:, request_context:,
                                               response_data:, is_chat_model:)
      # Convert duration from milliseconds to seconds for PostHog
      duration_seconds = duration_ms / 1000.0

      # Format input messages for PostHog
      ai_input = if is_chat_model
                   request_context[:conversation_for_api]
                 else
                   formatted_prompt = request_context[:prompt]&.format(request_context[:inputs] || {})
                   [{ role: "user", content: formatted_prompt }]
                 end

      # Extract token counts and output choices from response
      response_body = response_data[:response_obj]
      input_tokens = response_body&.dig("usage", "prompt_tokens") || 0
      output_tokens = response_body&.dig("usage", "completion_tokens") || 0

      # Format output choices for PostHog
      ai_output_choices = if response_body&.dig("choices")
                            response_body["choices"].map do |choice|
                              if choice.dig("message", "content")
                                { role: "assistant", content: choice.dig("message", "content") }
                              elsif choice["text"]
                                { role: "assistant", content: choice["text"] }
                              else
                                choice
                              end
                            end
                          else
                            []
                          end

      # Generate a trace ID if not provided (PostHog requires this)
      trace_id = SecureRandom.uuid

      properties = {
        # PostHog standard LLM observability properties
        '$ai_trace_id': trace_id,
        '$ai_model': api_request_params&.dig(:model) || current_params[:model],
        '$ai_provider': 'openai',
        '$ai_input': ai_input.to_json,
        '$ai_input_tokens': input_tokens,
        '$ai_output_choices': ai_output_choices.to_json,
        '$ai_output_tokens': output_tokens,
        '$ai_latency': duration_seconds,
        '$ai_http_status': response_data[:status_code] || (response_data[:success] ? 200 : 500),
        '$ai_base_url': 'https://api.openai.com/v1',
        '$ai_is_error': !response_data[:success]
      }

      # Add error details if present
      properties[:$ai_error] = _extract_error_message(response_data) if response_data[:error] || !response_data[:success]
      properties
    end
  end
end
