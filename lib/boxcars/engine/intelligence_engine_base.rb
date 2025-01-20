# frozen_string_literal: true

require 'intelligence'

module Boxcars
  # A engine that uses Cerebras's API
  class IntelligenceEngineBase < Engine
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

    def adapter(params:, api_key:)
      Intelligence::Adapter[provider].new(
        { key: api_key, chat_options: params }
      )
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
      params = default_model_params.merge(kwargs)
      api_key ||= lookup_provider_api_key(params: params)
      raise Error, "No API key found for #{provider}" unless api_key

      adapter = adapter(api_key: api_key, params: params)
      convo = prompt.as_intelligence_conversation(inputs: inputs)
      request = Intelligence::ChatRequest.new(adapter: adapter)
      response = request.chat(convo)
      return JSON.parse(response.body) if response.success?

      raise Error, (response&.reason_phrase || "No response from API #{provider}")
    rescue StandardError => e
      Boxcars.error("#{provider} Error: #{e.message}", :red)
      raise
    end

    # Run the engine with a question
    def run(question, **kwargs)
      prompt = Prompt.new(template: question)
      response = client(prompt: prompt, **kwargs)
      extract_answer(response)
    end

    private

    def extract_answer(response)
      # Handle different response formats
      if response["choices"]
        response["choices"].map { |c| c.dig("message", "content") || c["text"] }.join("\n").strip
      else
        response["output"] || response.to_s
      end
    end

    def check_response(response)
      return if response.present? && response.key?("choices")

      raise KeyError, "#{provider} API_KEY not valid" if response&.reason_phrase == "Unauthorized"

      raise ValueError, "#{provider} Error: #{response&.reason_phrase&.present? ? response.reason_phrase : response}"
    end
  end
end
