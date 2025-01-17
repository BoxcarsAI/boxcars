# frozen_string_literal: true

require "intelligence"
module Boxcars
  # A engine that uses Cerebras's API
  class Cerebras < Engine
    attr_reader :prompts, :cerebras_params, :model_kwargs, :batch_size

    # The default parameters to use when asking the engine
    DEFAULT_PARAMS = {
      model: "llama-3.3-70b",
      temperature: 0.1
    }.freeze

    # the default name of the engine
    DEFAULT_NAME = "Cerebras engine"
    # the default description of the engine
    DEFAULT_DESCRIPTION = "useful for when you need to use Cerebras to process complex content. " \
                          "Supports text, images, and other content types"

    def initialize(name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, prompts: [], batch_size: 20, **kwargs)
      @cerebras_params = DEFAULT_PARAMS.merge(kwargs)
      @prompts = prompts
      @batch_size = batch_size
      super(description: description, name: name)
    end

    # Get the Cerebras API client
    def self.adapter(params:, api_key: nil)
      api_key = Boxcars.configuration.cerebras_api_key(**params) if api_key.nil?
      raise ArgumentError, "Cerebras API key not configured" unless api_key

      Intelligence::Adapter[:cerebras].new(
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
      params = cerebras_params.merge(kwargs)
      adapter = Cerebras.adapter(api_key: api_key, params: params)
      raise Error, "Cerebras: No response from API" unless adapter

      convo = prompt.as_intelligence_conversation(inputs: inputs)
     raise Error, "Cerebras: No conversation" unless convo
      # Make API call
      request = Intelligence::ChatRequest.new(adapter: adapter)
      response = request.chat(convo)
      return JSON.parse(response.body) if response.success?

      raise Error, "Cerebras: #{response.reason_phrase}"
    rescue StandardError => e
      Boxcars.error("Cerebras Error: #{e.message}", :red)
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

      raise KeyError, "CEREBRAS_API_KEY not valid" if response&.reason_phrase == "Unauthorized"

      raise ValueError, "Cerebras error: #{response&.reason_phrase&.present? ? response.reason_phrase : response}"
    end

    def conversation_model?(_model)
      true
    end
  end
end
