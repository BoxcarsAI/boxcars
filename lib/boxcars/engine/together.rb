# frozen_string_literal: true

module Boxcars
  # A engine that uses Google's API
  class Together < IntelligenceBase
    # The default parameters to use when asking the engine
    DEFAULT_PARAMS = {
      model: "deepseek-ai/DeepSeek-R1-Distill-Llama-70B",
      temperature: 0.1
    }.freeze

    # the default name of the engine
    DEFAULT_NAME = "DeepSeek R1 Distill Llama 70B AI engine"
    # the default description of the engine
    DEFAULT_DESCRIPTION = "useful for when you need to use DeepSeek AI to process complex content. " \
                          "Supports text, images, and other content types"

    # A DeepSeek Engine is used by Boxcars to generate output from prompts
    # @param name [String] The name of the Engine. Defaults to classname.
    # @param description [String] A description of the Engine.
    # @param prompts [Array<Prompt>] The prompts to use for the Engine.
    # @param batch_size [Integer] The number of prompts to send to the Engine at a time.
    # @param kwargs [Hash] Additional parameters to pass to the Engine.
    def initialize(name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, prompts: [], batch_size: 20, **)
      super(provider: :together_ai, description:, name:, prompts:, batch_size:, **)
    end

    def default_model_params
      DEFAULT_PARAMS
    end

    def lookup_provider_api_key(params:)
      Boxcars.configuration.together_api_key(**params)
    end
  end
end
