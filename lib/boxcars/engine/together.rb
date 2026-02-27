# frozen_string_literal: true

module Boxcars
  # Engine that uses Together AI's OpenAI-compatible API.
  class Together < Openai
    DEFAULT_PARAMS = {
      model: "deepseek-ai/DeepSeek-R1-Distill-Llama-70B",
      temperature: 0.1,
      max_tokens: 4096
    }.freeze

    URI_BASE = "https://api.together.xyz/v1"

    DEFAULT_NAME = "DeepSeek R1 Distill Llama 70B AI engine"
    DEFAULT_DESCRIPTION = "useful for when you need to use DeepSeek AI to process complex content. " \
                          "Supports text, images, and other content types"

    def initialize(name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, prompts: [], batch_size: 20, **kwargs)
      super(name:, description:, prompts:, batch_size:, **DEFAULT_PARAMS.merge(kwargs))
    end

    def client(prompt:, inputs: {}, together_api_key: nil, **kwargs)
      super(prompt:, inputs:, openai_access_token: together_api_key, **kwargs)
    end

    def self.open_ai_client(openai_access_token: nil)
      access_token = Boxcars.configuration.together_api_key(together_api_key: openai_access_token)
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
