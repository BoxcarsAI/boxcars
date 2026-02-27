# frozen_string_literal: true

module Boxcars
  # Engine that uses Cerebras's OpenAI-compatible API.
  class Cerebras < Openai
    # The default parameters to use when asking the engine
    DEFAULT_PARAMS = {
      model: "llama-3.3-70b",
      temperature: 0.1,
      max_tokens: 4096
    }.freeze

    URI_BASE = "https://api.cerebras.ai/v1"

    DEFAULT_NAME = "Cerebras engine"
    DEFAULT_DESCRIPTION = "useful for when you need to use Cerebras to process complex content. " \
                          "Supports text, images, and other content types"

    def initialize(name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, prompts: [], batch_size: 20, **kwargs)
      super(name:, description:, prompts:, batch_size:, **DEFAULT_PARAMS.merge(kwargs))
    end

    def client(prompt:, inputs: {}, cerebras_api_key: nil, **kwargs)
      super(prompt:, inputs:, openai_access_token: cerebras_api_key, **kwargs)
    end

    def self.open_ai_client(openai_access_token: nil)
      access_token = Boxcars.configuration.cerebras_api_key(cerebras_api_key: openai_access_token)
      Boxcars::OpenAICompatibleClient.build(
        access_token:,
        uri_base: URI_BASE
      )
    end

    private

    def chat_model?(_model_name)
      true
    end
  end
end
