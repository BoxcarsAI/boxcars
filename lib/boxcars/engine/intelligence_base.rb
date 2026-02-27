# frozen_string_literal: true

require_relative 'unified_observability'

begin
  require "intelligence"
rescue LoadError
  # Optional dependency: kept for backward compatibility with custom engines.
end

module Boxcars
  # A Base class for all Intelligence Engines
  class IntelligenceBase < Engine
    include Boxcars::UnifiedObservability

    attr_reader :provider, :all_params

    # The base Intelligence Engine is used by other engines to generate output from prompts
    # @param provider [String] The provider of the Engine implemented by the Intelligence gem.
    # @param name [String] The name of the Engine. Defaults to classname.
    # @param description [String] A description of the Engine.
    # @param batch_size [Integer] The number of prompts to send to the Engine at a time.
    # @param kwargs [Hash] Additional parameters to pass to the Engine.
    def initialize(provider:, description:, name:, batch_size: 20, **kwargs)
      raise ArgumentError, "unknown keyword: :prompts" if kwargs.key?(:prompts)
      user_id = kwargs.delete(:user_id)
      @provider = provider
      # Start with defaults, merge other kwargs, then explicitly set model if provided in initialize
      @all_params = default_model_params.merge(kwargs)
      super(description:, name:, batch_size:, user_id:)
    end

    # can be overridden by provider subclass
    def default_model_params
      {}
    end

    def lookup_provider_api_key(params:)
      raise NotImplementedError, "lookup_provider_api_key method must be implemented by subclass"
    end

    def adapter(params:, api_key:)
      ensure_intelligence_available!
      Intelligence::Adapter.build! @provider do |config|
        config.key api_key
        config.chat_options params
      end
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
      ensure_intelligence_available!
      params = all_params.merge(kwargs)
      api_key ||= lookup_provider_api_key(params:)
      raise Error, "No API key found for #{provider}" unless api_key

      adapter = adapter(api_key:, params:)
      convo = prompt.as_intelligence_conversation(inputs:)
      request_context = { user_id:, prompt: prompt&.as_prompt(inputs:)&.[](:prompt), inputs:, conversation_for_api: convo.to_h }
      request = Intelligence::ChatRequest.new(adapter:)

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response_obj = nil

      begin
        response_obj = request.chat(convo)
        duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000

        if response_obj.success?
          success = true
          parsed_json_response = JSON.parse(response_obj.body)
          response_data = { success:, parsed_json: parsed_json_response, response_obj:,
                            status_code: response_obj.status }
          track_ai_generation(duration_ms:, current_params: params, request_context:, response_data:, provider:)
          parsed_json_response
        else
          success = false
          error_message = response_obj&.reason_phrase || "No response from API #{provider}"
          response_data = { success:, error: StandardError.new(error_message), response_obj:,
                            status_code: response_obj.status }
          track_ai_generation(duration_ms:, current_params: params, request_context:, response_data:, provider:)
          raise Error, error_message
        end
      rescue Error => e
        # Re-raise Error exceptions (like the one above) without additional tracking
        # since they were already tracked in the else branch
        Boxcars.error("#{provider} Error: #{e.message}", :red)
        raise
      rescue StandardError => e
        duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000
        success = false
        error_obj = e
        response_data = { success:, error: error_obj, response_obj:, status_code: response_obj&.status }
        track_ai_generation(duration_ms:, current_params: params, request_context:, response_data:, provider:)
        Boxcars.error("#{provider} Error: #{e.message}", :red)
        raise
      end
    end

    private

    def ensure_intelligence_available!
      return if intelligence_available?

      raise Boxcars::ConfigurationError,
            "IntelligenceBase requires the `intelligence` gem. Add `gem \"intelligence\"` to your application to use it."
    end

    def intelligence_available?
      defined?(::Intelligence::Adapter) && defined?(::Intelligence::ChatRequest)
    end

  end
end
