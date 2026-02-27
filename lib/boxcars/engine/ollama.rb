# frozen_string_literal: true

require 'json'

module Boxcars
  # An engine that uses a local Ollama API (OpenAI-compatible).
  class Ollama < Engine
    include UnifiedObservability
    include OpenAICompatibleChatHelpers

    attr_reader :prompts, :model_kwargs, :batch_size, :ollama_params

    DEFAULT_PARAMS = {
      model: "llama3",
      temperature: 0.1,
      max_tokens: 4096
    }.freeze
    DEFAULT_NAME = "Ollama engine"
    DEFAULT_DESCRIPTION = "useful for when you need to use local AI to answer questions. " \
                          "You should ask targeted questions"

    def initialize(name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, prompts: [], batch_size: 2, **kwargs)
      user_id = kwargs.delete(:user_id)
      @ollama_params = DEFAULT_PARAMS.merge(kwargs)
      @prompts = prompts
      @batch_size = batch_size
      super(description:, name:, user_id:)
    end

    def self.provider_client
      # The OpenAI client expects an API key even for local endpoints.
      Boxcars::OpenAIClient.build(
        access_token: "ollama-dummy-key",
        uri_base: "http://localhost:11434/v1"
      )
    end

    def client(prompt:, inputs: {}, **kwargs)
      start_time = Time.now
      response_data = { response_obj: nil, parsed_json: nil, success: false, error: nil, status_code: nil }
      current_params = @ollama_params.merge(kwargs)
      current_prompt_object = normalize_prompt_object(prompt)
      api_request_params = nil

      begin
        clnt = self.class.provider_client
        api_request_params = prepare_openai_compatible_chat_request(current_prompt_object, inputs, current_params)

        log_messages_debug(api_request_params[:messages]) if Boxcars.configuration.log_prompts && api_request_params[:messages]

        execute_openai_compatible_chat_call(
          client: clnt,
          api_request_params: api_request_params,
          response_data: response_data,
          success_check: ->(raw) { raw["choices"] },
          unknown_error_message: "Unknown Ollama API Error",
          error_class: Error
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
          provider: :ollama
        )
      end

      ollama_handle_call_outcome(response_data:)
    end

    def default_params
      @ollama_params
    end

    private

    def ollama_handle_call_outcome(response_data:)
      if response_data[:error]
        Boxcars.error("Ollama Error: #{response_data[:error].message} (#{response_data[:error].class.name})", :red)
        raise response_data[:error]
      elsif !response_data[:success]
        err_details = response_data.dig(:response_obj, "error")
        msg = if err_details
                err_details.is_a?(Hash) ? err_details['message'] : err_details.to_s
              else
                "Unknown error from Ollama API"
              end
        raise Error, msg
      else
        response_data[:parsed_json]
      end
    end
  end
end
