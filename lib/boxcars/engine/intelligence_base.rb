# frozen_string_literal: true

require 'intelligence'
require 'securerandom'

module Boxcars
  # A Base class for all Intelligence Engines
  class IntelligenceBase < Engine
    attr_reader :provider, :all_params

    # The base Intelligence Engine is used by other engines to generate output from prompts
    # @param provider [String] The provider of the Engine implemented by the Intelligence gem.
    # @param name [String] The name of the Engine. Defaults to classname.
    # @param description [String] A description of the Engine.
    # @param prompts [Array<Prompt>] The prompts to use for the Engine.
    # @param batch_size [Integer] The number of prompts to send to the Engine at a time.
    # @param kwargs [Hash] Additional parameters to pass to the Engine.
    def initialize(provider:, description:, name:, prompts: [], batch_size: 20, **kwargs)
      @provider = provider
      @all_params = default_model_params.merge(kwargs)
      super(description: description, name: name, prompts: prompts, batch_size: batch_size)
    end

    # can be overridden by provider subclass
    def default_model_params
      {}
    end

    def lookup_provider_api_key(params:)
      raise NotImplementedError, "lookup_provider_api_key method must be implemented by subclass"
    end

    def adapter(api_key:)
      Intelligence::Adapter[provider].new(api_key)
    end

    # Process different content types
    def process_content(content)
      case content
      when String
        { type: "text", text: content }
      when Hash
        validate_content(content)
      when Array
        content.map { |c| process_content(c) }
      else
        raise ArgumentError, "Unsupported content type: #{content.class}"
      end
    end

    # Validate content structure
    def validate_content(content)
      raise ArgumentError, "Content must have type and text fields" unless content[:type] && content[:text]

      content
    end

    # Get an answer from the engine
    def client(prompt:, inputs: {}, api_key: nil, **kwargs)
      start_time = Time.now
      response_data = { response_obj: nil, parsed_json: nil, success: false, error: nil }
      current_params = nil
      conversation_for_api = nil

      begin
        current_params, conversation_for_api, effective_api_key = _prepare_request_data(prompt: prompt, inputs: inputs,
                                                                                        api_key: api_key, **kwargs)
        response_data = _execute_api_call(
          conversation_for_api: conversation_for_api,
          effective_api_key: effective_api_key
        )
      rescue StandardError => e
        response_data[:error] = e
        response_data[:success] = false
      ensure
        duration_ms = ((Time.now - start_time) * 1000).round
        request_context = {
          prompt: prompt,
          inputs: inputs,
          conversation_for_api: conversation_for_api
        }
        properties = _build_observability_properties(
          duration_ms: duration_ms,
          current_params: current_params,
          request_context: request_context,
          response_data: response_data
        )
        Boxcars::Observability.track(event: '$ai_generation', properties: properties.compact)
      end

      _handle_call_outcome(response_data: response_data)
    end

    # Run the engine with a question
    def run(question, **kwargs)
      prompt = Prompt.new(template: question)
      response = client(prompt: prompt, **kwargs)
      extract_answer(response)
    end

    private

    def _prepare_request_data(prompt:, inputs:, api_key:, **kwargs)
      current_params = all_params.merge(kwargs)
      effective_api_key = api_key || lookup_provider_api_key(params: current_params)
      raise Error, "No API key found for #{provider}" unless effective_api_key

      conversation_for_api = prompt.as_intelligence_conversation(inputs: inputs)
      [current_params, conversation_for_api, effective_api_key]
    end

    def _execute_api_call(conversation_for_api:, effective_api_key:)
      parsed_json = nil
      success = false

      adapter = adapter(api_key: effective_api_key)
      request = Intelligence::ChatRequest.new(adapter:)
      response_obj = request.chat(conversation_for_api) # Actual API call

      if response_obj.success?
        parsed_json = JSON.parse(response_obj.body)
        success = true
      else
        success = false
        # Error will be handled by _handle_call_outcome
      end
      { response_obj: response_obj, parsed_json: parsed_json, success: success, error: nil }
    end

    def _build_observability_properties(duration_ms:, current_params:, request_context:, response_data:)
      # Convert duration from milliseconds to seconds for PostHog
      duration_seconds = duration_ms / 1000.0

      # Format input messages for PostHog
      ai_input = _extract_prompt_content(request_context)

      # Extract token counts from response if available
      response_body = response_data[:parsed_json]
      input_tokens = _extract_input_tokens(response_body)
      output_tokens = _extract_output_tokens(response_body)

      # Format output choices for PostHog
      ai_output_choices = _extract_output_choices(response_body)

      # Generate a trace ID (PostHog requires this)
      trace_id = SecureRandom.uuid

      properties = {
        # PostHog standard LLM observability properties
        '$ai_trace_id': trace_id,
        '$ai_model': _extract_model_name(current_params),
        '$ai_provider': @provider.to_s,
        '$ai_input': ai_input.to_json,
        '$ai_input_tokens': input_tokens,
        '$ai_output_choices': ai_output_choices.to_json,
        '$ai_output_tokens': output_tokens,
        '$ai_latency': duration_seconds,
        '$ai_http_status': _extract_status_code(response_data[:response_obj]) || (response_data[:success] ? 200 : 500),
        '$ai_base_url': _get_base_url_for_provider(@provider),
        '$ai_is_error': !response_data[:success]
      }

      # Add error details if present
      if response_data[:error] || !response_data[:success]
        properties[:$ai_error] = _extract_error_message_for_posthog(response_data)
      end

      properties
    end

    def _extract_model_name(current_params)
      current_params&.dig(:model) || current_params&.dig("model") || @provider.to_s
    end

    def _extract_prompt_content(request_context)
      conv_messages = request_context[:conversation_for_api]&.messages
      return [{ role: "user", content: request_context[:prompt].to_s }] unless conv_messages

      conv_messages.map do |message|
        content_text = _extract_message_content(message)
        { role: message.role, content: content_text }
      end
    end

    def _extract_message_content(message)
      # Handle Intelligence::Message objects and extract text content
      if message.respond_to?(:content)
        message.content
      elsif message.respond_to?(:parts) && message.parts&.first.respond_to?(:text)
        message.parts&.first&.text
      else
        message.to_s
      end
    end

    def _extract_input_tokens(response_body)
      return 0 unless response_body

      # Try different token count locations based on provider
      response_body.dig("usage", "prompt_tokens") ||
        response_body.dig("meta", "tokens", "input_tokens") ||
        response_body.dig("token_count", "prompt_tokens") ||
        0
    end

    def _extract_output_tokens(response_body)
      return 0 unless response_body

      # Try different token count locations based on provider
      response_body.dig("usage", "completion_tokens") ||
        response_body.dig("meta", "tokens", "output_tokens") ||
        response_body.dig("token_count", "completion_tokens") ||
        0
    end

    def _extract_output_choices(response_body)
      return [] unless response_body

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

    def _get_base_url_for_provider(provider)
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
      else
        "https://api.#{provider}.com/v1"
      end
    end

    def _extract_error_message_for_posthog(response_data)
      if response_data[:error]
        response_data[:error].message
      elsif response_data[:response_obj]
        response_data[:response_obj].reason_phrase || "API call failed with status #{response_data[:response_obj].status}"
      else
        "Unknown error"
      end
    end

    def _extract_status_code(response_obj)
      response_obj.respond_to?(:status) ? response_obj.status : nil
    end

    def _handle_call_outcome(response_data:)
      if response_data[:error]
        Boxcars.error("#{provider} Error: #{response_data[:error].message}", :red)
        raise response_data[:error]
      elsif !response_data[:success]
        raise Error, (response_data[:response_obj]&.reason_phrase || "No response or error from API #{provider}")
      else
        response_data[:parsed_json]
      end
    end

    def extract_answer(response)
      # Handle different response formats
      if response["choices"]
        response["choices"].map { |c| c.dig("message", "content") || c["text"] }.join("\n").strip
      elsif response["candidates"]
        response["candidates"].map { |c| c.dig("content", "parts", 0, "text") }.join("\n").strip
      elsif response["text"]
        response["text"]
      else
        response["output"] || response.to_s
      end
    end

    def check_response(response)
      return if response.is_a?(Hash) && response.key?("choices")

      raise Error, "Invalid response from #{provider}: #{response}"
    end
  end
end
