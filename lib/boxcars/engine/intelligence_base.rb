# frozen_string_literal: true

require 'intelligence'
require 'securerandom'

module Boxcars
  # A Base class for all Intelligence Engines
  class IntelligenceBase < Engine
    include UnifiedObservability
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
      Intelligence::Adapter[provider].new({ api_key: api_key })
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
    def client(prompt:, inputs: {}, api_key: nil, **)
      start_time = Time.now
      response_data = { response_obj: nil, parsed_json: nil, success: false, error: nil }
      current_params = nil
      conversation_for_api = nil

      begin
        current_params, conversation_for_api, effective_api_key = _prepare_request_data(prompt: prompt, inputs: inputs,
                                                                                        api_key: api_key, **)
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
        track_ai_generation(
          duration_ms: duration_ms,
          current_params: current_params,
          request_context: request_context,
          response_data: response_data,
          provider: @provider
        )
      end

      _handle_call_outcome(response_data: response_data)
    end

    # Run the engine with a question
    def run(question, **)
      prompt = Prompt.new(template: question)
      response = client(prompt: prompt, **)
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
