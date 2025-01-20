# frozen_string_literal: true

module Boxcars
  # A engine that uses Google's API
  class GoogleEngine < IntelligenceEngineBase
    # The default parameters to use when asking the engine
    DEFAULT_PARAMS = {
      model: "gemini-1.5-flash-latest",
      temperature: 0.1
    }.freeze

    # the default name of the engine
    DEFAULT_NAME = "Google Vertex AI engine"
    # the default description of the engine
    DEFAULT_DESCRIPTION = "useful for when you need to use Google Vertex AI to process complex content. " \
                          "Supports text, images, and other content types"

    # A Google Engine is used by Boxcars to generate output from prompts
    # @param name [String] The name of the Engine. Defaults to classname.
    # @param description [String] A description of the Engine.
    # @param prompts [Array<Prompt>] The prompts to use for the Engine.
    # @param batch_size [Integer] The number of prompts to send to the Engine at a time.
    # @param kwargs [Hash] Additional parameters to pass to the Engine.
    def initialize(name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, prompts: [], batch_size: 20, **kwargs)
      super(provider: :google, description: description, name: name, prompts: prompts, batch_size: batch_size, **kwargs)
    end

    def default_model_params
      DEFAULT_PARAMS
    end

    def lookup_provider_api_key(params:)
      Boxcars.configuration.gemini_api_key(**params)
    end
  end
end
