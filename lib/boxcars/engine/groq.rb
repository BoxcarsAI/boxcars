# frozen_string_literal: true

require 'json'

module Boxcars
  # An engine that uses Groq's API.
  class Groq < Engine
    include UnifiedObservability
    include OpenAICompatibleChatHelpers

    attr_reader :prompts, :groq_params, :model_kwargs, :batch_size

    DEFAULT_PARAMS = {
      model: "llama3-70b-8192",
      temperature: 0.1,
      max_tokens: 4096
    }.freeze
    DEFAULT_NAME = "Groq engine"
    DEFAULT_DESCRIPTION = "useful for when you need to use Groq AI to answer questions. " \
                          "You should ask targeted questions"

    def initialize(name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, prompts: [], batch_size: 20, **kwargs)
      user_id = kwargs.delete(:user_id)
      @groq_params = DEFAULT_PARAMS.merge(kwargs)
      @prompts = prompts
      @batch_size = batch_size
      super(description:, name:, user_id:)
    end

    def self.provider_client(groq_api_key: nil)
      access_token = Boxcars.configuration.groq_api_key(groq_api_key:)
      Boxcars::OpenAIClient.build(
        access_token:,
        uri_base: "https://api.groq.com/openai/v1"
      )
    end

    def client(prompt:, inputs: {}, groq_api_key: nil, **kwargs)
      start_time = Time.now
      response_data = { response_obj: nil, parsed_json: nil, success: false, error: nil, status_code: nil }
      current_params = @groq_params.merge(kwargs)
      current_prompt_object = normalize_prompt_object(prompt)
      api_request_params = nil

      begin
        clnt = self.class.provider_client(groq_api_key:)
        api_request_params = prepare_openai_compatible_chat_request(current_prompt_object, inputs, current_params)

        log_messages_debug(api_request_params[:messages]) if Boxcars.configuration.log_prompts && api_request_params[:messages]

        execute_openai_compatible_chat_call(
          client: clnt,
          api_request_params: api_request_params,
          response_data: response_data,
          success_check: ->(raw) { raw["choices"] },
          unknown_error_message: "Unknown Groq API Error"
        )
      rescue StandardError => e
        handle_openai_compatible_standard_error(e, response_data)
      ensure
        duration_ms = ((Time.now - start_time) * 1000).round
        request_context = {
          prompt: current_prompt_object,
          inputs:,
          conversation_for_api: api_request_params&.dig(:messages),
          user_id:
        }
        track_ai_generation(
          duration_ms:,
          current_params:,
          request_context:,
          response_data:,
          provider: :groq
        )
      end

      raise response_data[:error] if response_data[:error]

      response_data[:parsed_json]
    end

    private

    def default_params
      @groq_params
    end
  end
end
