# frozen_string_literal: true

require 'json'
require 'securerandom'

module Boxcars
  # Unified observability module that provides PostHog-centric tracking for all engines
  # Uses standardized $ai_* properties as defined by PostHog's LLM observability spec
  # rubocop:disable Metrics/ModuleLength
  module UnifiedObservability
    private

    # Main tracking method that all engines should call
    def track_ai_generation(duration_ms:, current_params:, request_context:, response_data:, provider:)
      properties = build_unified_observability_properties(
        duration_ms: duration_ms,
        current_params: current_params,
        request_context: request_context,
        response_data: response_data,
        provider: provider
      )
      Boxcars::Observability.track(event: '$ai_generation', properties: properties.compact)
    end

    # Build standardized PostHog properties for any engine
    def build_unified_observability_properties(duration_ms:, current_params:, request_context:, response_data:, provider:)
      # Convert duration from milliseconds to seconds for PostHog
      duration_seconds = duration_ms / 1000.0

      # Format input messages for PostHog
      ai_input = extract_ai_input(request_context, provider)

      # Extract token counts from response if available
      input_tokens = extract_input_tokens(response_data, provider)
      output_tokens = extract_output_tokens(response_data, provider)

      # Format output choices for PostHog
      ai_output_choices = extract_output_choices(response_data, provider)

      # Generate a trace ID (PostHog requires this)
      trace_id = SecureRandom.uuid

      properties = {
        # PostHog standard LLM observability properties
        '$ai_trace_id': trace_id,
        '$ai_model': extract_model_name(current_params, provider),
        '$ai_provider': provider.to_s,
        '$ai_input': ai_input.to_json,
        '$ai_input_tokens': input_tokens,
        '$ai_output_choices': ai_output_choices.to_json,
        '$ai_output_tokens': output_tokens,
        '$ai_latency': duration_seconds,
        '$ai_http_status': extract_status_code(response_data) || (response_data[:success] ? 200 : 500),
        '$ai_base_url': get_base_url_for_provider(provider),
        '$ai_is_error': !response_data[:success]
      }

      # Add error details if present
      properties[:$ai_error] = extract_error_message(response_data, provider) if response_data[:error] || !response_data[:success]

      properties
    end

    # Provider-specific input extraction with fallbacks
    def extract_ai_input(request_context, provider)
      case provider.to_s
      when 'openai'
        extract_openai_input(request_context)
      when 'anthropic'
        extract_anthropic_input(request_context)
      else
        extract_generic_input(request_context)
      end
    end

    def extract_openai_input(request_context)
      if request_context[:conversation_for_api].is_a?(Array)
        request_context[:conversation_for_api]
      else
        formatted_prompt = request_context[:prompt]&.format(request_context[:inputs] || {})
        [{ role: "user", content: formatted_prompt }]
      end
    end

    def extract_anthropic_input(request_context)
      content = []

      # Add system prompt if present
      system_prompt = request_context.dig(:conversation_for_api, :system)
      content << { role: "system", content: system_prompt } if system_prompt && !system_prompt.to_s.strip.empty?

      # Add messages
      messages = request_context.dig(:conversation_for_api, :messages)
      if messages.is_a?(Array)
        messages.each do |msg|
          content << { role: msg[:role], content: extract_message_content(msg[:content]) }
        end
      elsif request_context[:prompt]
        prompt_text = if request_context[:prompt].respond_to?(:template)
                        request_context[:prompt].template
                      else
                        request_context[:prompt].to_s
                      end
        content << { role: "user", content: prompt_text }
      end

      content
    end

    def extract_generic_input(request_context)
      # For IntelligenceBase-style engines
      conv_messages = request_context[:conversation_for_api]&.messages
      return [{ role: "user", content: request_context[:prompt].to_s }] unless conv_messages

      conv_messages.map do |message|
        content_text = extract_message_content(message)
        { role: message.role, content: content_text }
      end
    end

    def extract_message_content(content)
      case content
      when String
        content
      when Array
        content.map { |part| part.is_a?(Hash) ? part[:text] || part.to_s : part.to_s }.join("\n")
      when Hash
        content[:text] || content.to_s
      else
        if content.respond_to?(:content)
          content.content
        elsif content.respond_to?(:parts) && content.parts&.first.respond_to?(:text)
          content.parts&.first&.text
        else
          content.to_s
        end
      end
    end

    # Provider-specific token extraction with fallbacks
    def extract_input_tokens(response_data, provider)
      # Only extract tokens from parsed JSON, not from raw response objects
      return 0 unless response_data[:parsed_json]

      response_body = response_data[:parsed_json]

      case provider.to_s
      when 'anthropic'
        response_body.dig("usage", "input_tokens") || 0
      when 'openai'
        response_body.dig("usage", "prompt_tokens") || 0
      else
        # Try common locations
        response_body.dig("usage", "prompt_tokens") ||
          response_body.dig("usage", "input_tokens") ||
          response_body.dig("meta", "tokens", "input_tokens") ||
          response_body.dig("token_count", "prompt_tokens") ||
          0
      end
    end

    def extract_output_tokens(response_data, provider)
      # Only extract tokens from parsed JSON, not from raw response objects
      return 0 unless response_data[:parsed_json]

      response_body = response_data[:parsed_json]

      case provider.to_s
      when 'anthropic'
        response_body.dig("usage", "output_tokens") || 0
      when 'openai'
        response_body.dig("usage", "completion_tokens") || 0
      else
        # Try common locations
        response_body.dig("usage", "completion_tokens") ||
          response_body.dig("usage", "output_tokens") ||
          response_body.dig("meta", "tokens", "output_tokens") ||
          response_body.dig("token_count", "completion_tokens") ||
          0
      end
    end

    # Provider-specific output extraction with fallbacks
    def extract_output_choices(response_data, provider)
      # Only extract output choices from parsed JSON, not from raw response objects
      return [] unless response_data[:parsed_json]

      response_body = response_data[:parsed_json]

      case provider.to_s
      when 'anthropic'
        extract_anthropic_output_choices(response_body)
      when 'openai'
        extract_openai_output_choices(response_body)
      else
        extract_generic_output_choices(response_body)
      end
    end

    def extract_anthropic_output_choices(response_body)
      # Handle both original Anthropic format and transformed format
      if response_body["content"].is_a?(Array)
        # Original format from Anthropic API
        content_text = response_body["content"].map { |c| c["text"] }.join("\n")
        [{ role: "assistant", content: content_text }]
      elsif response_body["completion"]
        # Transformed format after Anthropic engine processing
        [{ role: "assistant", content: response_body["completion"] }]
      else
        []
      end
    end

    def extract_openai_output_choices(response_body)
      if response_body["choices"]
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
    end

    def extract_generic_output_choices(response_body)
      # Handle different response formats
      if response_body["choices"]
        response_body["choices"].map do |choice|
          if choice.dig("message", "content")
            { role: "assistant", content: choice.dig("message", "content") }
          elsif choice["text"]
            { role: "assistant", content: choice["text"] }
          else
            choice
          end
        end
      elsif response_body["text"]
        [{ role: "assistant", content: response_body["text"] }]
      elsif response_body["message"]
        [{ role: "assistant", content: response_body["message"] }]
      elsif response_body["candidates"]
        response_body["candidates"].map do |candidate|
          content = candidate.dig("content", "parts", 0, "text") || candidate.to_s
          { role: "assistant", content: content }
        end
      else
        []
      end
    end

    def extract_model_name(current_params, provider)
      current_params&.dig(:model) ||
        current_params&.dig("model") ||
        get_default_model_for_provider(provider)
    end

    def get_default_model_for_provider(provider)
      case provider.to_s
      when 'openai'
        'gpt-4o-mini'
      when 'anthropic'
        'claude-3-5-sonnet-20240620'
      when 'cerebras'
        'llama-3.3-70b'
      else
        provider.to_s
      end
    end

    def get_base_url_for_provider(provider)
      case provider.to_s
      when 'cohere'
        'https://api.cohere.ai/v1'
      when 'anthropic'
        'https://api.anthropic.com/v1'
      when 'google', 'gemini'
        'https://generativelanguage.googleapis.com/v1'
      when 'groq'
        'https://api.groq.com/openai/v1'
      when 'cerebras'
        'https://api.cerebras.ai/v1'
      when 'openai'
        'https://api.openai.com/v1'
      else
        "https://api.#{provider}.com/v1"
      end
    end

    def extract_error_message(response_data, provider)
      if response_data[:error]
        response_data[:error].message
      elsif response_data[:response_obj]
        case provider.to_s
        when 'openai'
          extract_openai_error_message(response_data[:response_obj])
        when 'anthropic'
          extract_anthropic_error_message(response_data[:response_obj])
        else
          # For failed responses, try to get error from reason_phrase or fallback
          if response_data[:response_obj].respond_to?(:reason_phrase)
            response_data[:response_obj].reason_phrase || "API call failed"
          else
            "API call failed"
          end
        end
      else
        "Unknown error"
      end
    end

    def extract_openai_error_message(response_obj)
      if response_obj.respond_to?(:body) && response_obj.body
        begin
          parsed_body = JSON.parse(response_obj.body)
          if parsed_body["error"]
            err = parsed_body["error"]
            "#{err['type']}: #{err['message']}"
          else
            response_obj.respond_to?(:reason_phrase) ? response_obj.reason_phrase : "Unknown OpenAI error"
          end
        rescue JSON::ParserError
          response_obj.respond_to?(:reason_phrase) ? response_obj.reason_phrase : "Unknown OpenAI error"
        end
      else
        response_obj.respond_to?(:reason_phrase) ? response_obj.reason_phrase : "Unknown OpenAI error"
      end
    end

    def extract_anthropic_error_message(response_obj)
      if response_obj.respond_to?(:body) && response_obj.body
        begin
          parsed_body = JSON.parse(response_obj.body)
          parsed_body.dig("error", "message") ||
            (response_obj.respond_to?(:reason_phrase) ? response_obj.reason_phrase : "Unknown Anthropic error")
        rescue JSON::ParserError
          response_obj.respond_to?(:reason_phrase) ? response_obj.reason_phrase : "Unknown Anthropic error"
        end
      else
        response_obj.respond_to?(:reason_phrase) ? response_obj.reason_phrase : "Unknown Anthropic error"
      end
    end

    def extract_status_code(response_data)
      response_data[:status_code] ||
        (response_data[:response_obj].respond_to?(:status) ? response_data[:response_obj].status : nil)
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
