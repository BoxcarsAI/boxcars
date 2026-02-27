# frozen_string_literal: true

module Boxcars
  # Engine that uses Google's Gemini OpenAI-compatible API.
  class Google < Openai
    DEFAULT_PARAMS = {
      model: "gemini-1.5-flash-latest",
      temperature: 0.1,
      max_tokens: 4096
    }.freeze

    URI_BASE = "https://generativelanguage.googleapis.com/v1beta/"

    DEFAULT_NAME = "Google Vertex AI engine"
    DEFAULT_DESCRIPTION = "useful for when you need to use Google Vertex AI to process complex content. " \
                          "Supports text, images, and other content types"

    def initialize(name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, prompts: [], batch_size: 20, **kwargs)
      super(name:, description:, prompts:, batch_size:, **DEFAULT_PARAMS.merge(kwargs))
    end

    # Supports both `gemini_api_key:` and legacy `google_api_key:` naming.
    def client(prompt:, inputs: {}, gemini_api_key: nil, google_api_key: nil, **kwargs)
      kwargs = kwargs.dup
      kwargs.delete(:openai_client_backend)
      kwargs.delete(:client_backend)
      key = gemini_api_key || google_api_key
      super(prompt:, inputs:, openai_access_token: key, openai_client_backend: :ruby_openai, **kwargs)
    end

    def self.open_ai_client(openai_access_token: nil, backend: nil)
      access_token = Boxcars.configuration.gemini_api_key(gemini_api_key: openai_access_token)
      Boxcars::OpenAIClientAdapter.build(
        access_token:,
        uri_base: URI_BASE,
        backend: backend || :ruby_openai
      )
    end

    private

    def chat_model?(_model_name)
      true
    end
  end
end
