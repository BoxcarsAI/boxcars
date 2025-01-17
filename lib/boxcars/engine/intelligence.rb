# frozen_string_literal: true

module Boxcars
  # A engine that uses Intelligence's API
  class Intelligence < Engine
    attr_reader :prompts, :intelligence_params, :model_kwargs, :batch_size

    # The default parameters to use when asking the engine
    DEFAULT_PARAMS = {
      model: "intelligence-1.0",
      temperature: 0.1
    }.freeze

    # the default name of the engine
    DEFAULT_NAME = "Intelligence engine"
    # the default description of the engine
    DEFAULT_DESCRIPTION = "useful for when you need to use Intelligence to process complex content. " \
                          "Supports text, images, and other content types"

    def initialize(name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, prompts: [], batch_size: 20, **kwargs)
      begin
        require 'intelligence'
      rescue LoadError => _e
        raise LoadError,
              "The intelligence gem is required. Please add 'gem \"intelligence\"' to your Gemfile and run bundle install"
      end

      @intelligence_params = DEFAULT_PARAMS.merge(kwargs)
      @prompts = prompts
      @batch_size = batch_size
      super(description: description, name: name)
    end

    # Get the Intelligence API client
    def self.intelligence_client(api_key: nil)
      api_key ||= Boxcars.configuration.intelligence_api_key
      raise ArgumentError, "Intelligence API key not configured" unless api_key

      Client.new(api_key: api_key)
    end

    # Stream responses from the Intelligence API
    def stream(prompt:, inputs: {}, api_key: nil, &block)
      client = Intelligence.intelligence_client(api_key: api_key)
      params = intelligence_params.merge(stream: true)

      processed_prompt = if conversation_model?(params[:model])
                           prompt.as_messages(inputs)
                         else
                           { prompt: prompt.as_prompt(inputs: inputs) }
                         end

      processed_prompt[:content] = process_content(processed_prompt[:content]) if processed_prompt[:content]

      client.stream(parameters: params.merge(processed_prompt), &block)
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
      client = Intelligence.intelligence_client(api_key: api_key)
      params = intelligence_params.merge(kwargs)

      processed_prompt = if conversation_model?(params[:model])
                           prompt.as_messages(inputs)
                         else
                           { prompt: prompt.as_prompt(inputs: inputs) }
                         end

      # Add content processing
      processed_prompt[:content] = process_content(processed_prompt[:content]) if processed_prompt[:content]

      Boxcars.debug("Sending to Intelligence:\n#{processed_prompt}", :cyan) if Boxcars.configuration.log_prompts

      # Make API call
      response = client.generate(parameters: params.merge(processed_prompt))
      check_response(response)
      response
    rescue StandardError => e
      Boxcars.error("Intelligence Error: #{e.message}", :red)
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
      if response["error"]
        code = response.dig("error", "code")
        msg = response.dig("error", "message") || "unknown error"
        raise KeyError, "INTELLIGENCE_API_KEY not valid" if code == "invalid_api_key"

        raise ValueError, "Intelligence error: #{msg}"
      end

      # Validate response structure
      return if response["choices"] || response["output"]

      raise Error, "Invalid response format from Intelligence API"
    end

    def conversation_model?(_model)
      true
    end
  end
end
