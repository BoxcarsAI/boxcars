# frozen_string_literal: true

# Boxcars - a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A engine that uses Cohere's API.
  class Cohere < IntelligenceBase
    # The default parameters to use when asking the engine.
    DEFAULT_PARAMS = {
      model: "command-r-plus",
      max_tokens: 4000,
      # max_input_tokens: 1000, # This might be specific to the old implementation or handled by Intelligence gem
      temperature: 0.2
    }.freeze

    # the default name of the engine
    DEFAULT_NAME = "Cohere engine"
    # the default description of the engine
    DEFAULT_DESCRIPTION = "useful for when you need to use Cohere AI to answer questions. " \
                          "You should ask targeted questions"

    # Initializes the Cohere engine.
    # @param name [String] The name of the engine.
    # @param description [String] A description of the engine.
    # @param prompts [Array<Boxcars::Prompt>] The prompts to use for the engine.
    # @param batch_size [Integer] The number of prompts to send to the engine at a time.
    # @param kwargs [Hash] Additional parameters to pass to the underlying Intelligence gem adapter.
    def initialize(name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, prompts: [], batch_size: 20, **kwargs)
      super(
        provider: :cohere,
        name: name,
        description: description,
        prompts: prompts,
        batch_size: batch_size,
        **kwargs
      )
    end

    # Returns the default parameters for the Cohere model.
    # @return [Hash]
    def default_model_params
      DEFAULT_PARAMS
    end

    # Looks up the Cohere API key from the Boxcars configuration.
    # @param params [Hash] Additional parameters (not used by this method for Cohere).
    # @return [String] The Cohere API key.
    def lookup_provider_api_key(params: {})
      Boxcars.configuration.cohere_api_key(**params)
    end

    # NOTE: The `client` and `run` methods are inherited from IntelligenceBase.
    # The IntelligenceBase#client method will use an adapter like Intelligence::Adapter[:cohere].
    # Any Cohere-specific request/response handling should ideally be within that adapter.

    # The `extract_answer` method from IntelligenceBase might need to be overridden
    # if Cohere's response structure is not covered by the default implementation.
    # For example, if the old implementation was:
    # def extract_answer(response)
    #   response[:text]
    # end
    # This logic would now typically reside in the Intelligence::Adapter::Cohere
    # or if necessary, be overridden here. For now, we rely on IntelligenceBase's default.

    # Methods like `conversation_model?`, `engine_type`, `modelname_to_contextsize`,
    # `max_tokens_for_prompt`, `default_prefixes`, and `check_response`
    # are removed as their responsibilities are either handled by IntelligenceBase,
    # the Intelligence gem adapter, or are no longer applicable in this new structure.
  end
end
