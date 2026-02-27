# frozen_string_literal: true

require 'json'

module Boxcars
  # An engine that uses GeminiAI's API via an OpenAI-compatible interface.
  class GeminiAi < Engine
    include UnifiedObservability
    include OpenAICompatibleChatHelpers

    attr_reader :prompts, :llm_params, :model_kwargs, :batch_size

    DEFAULT_PARAMS = {
      model: "gemini-2.5-flash",
      temperature: 0.1
    }.freeze
    DEFAULT_NAME = "GeminiAI engine"
    DEFAULT_DESCRIPTION = "useful for when you need to use Gemini AI to answer questions. " \
                          "You should ask targeted questions"

    def initialize(name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, prompts: [], batch_size: 20, **kwargs)
      user_id = kwargs.delete(:user_id)
      @llm_params = DEFAULT_PARAMS.merge(kwargs)
      @prompts = prompts
      @batch_size = batch_size
      super(description:, name:, user_id:)
    end

    def self.gemini_client(gemini_api_key: nil)
      access_token = Boxcars.configuration.gemini_api_key(gemini_api_key:)
      Boxcars::OpenAICompatibleClient.build(
        access_token: access_token,
        uri_base: "https://generativelanguage.googleapis.com/v1beta/"
      )
    end

    def client(prompt:, inputs: {}, gemini_api_key: nil, **kwargs)
      start_time = Time.now
      response_data = { response_obj: nil, parsed_json: nil, success: false, error: nil, status_code: nil }
      current_params = @llm_params.merge(kwargs)
      api_request_params = nil
      current_prompt_object = normalize_prompt_object(prompt)

      begin
        clnt = GeminiAi.gemini_client(gemini_api_key:)
        api_request_params = prepare_openai_compatible_chat_request(current_prompt_object, inputs, current_params)

        log_messages_debug(api_request_params[:messages]) if Boxcars.configuration.log_prompts && api_request_params[:messages]
        execute_openai_compatible_chat_call(
          client: clnt,
          api_request_params: api_request_params,
          response_data: response_data,
          success_check: ->(raw) { raw["choices"] || raw["candidates"] },
          unknown_error_message: "Unknown Gemini API Error",
          preserve_existing_error: false
        )
        normalize_gemini_response!(response_data)
      rescue StandardError => e
        handle_openai_compatible_standard_error(e, response_data)
      ensure
        duration_ms = ((Time.now - start_time) * 1000).round
        request_context = {
          prompt: current_prompt_object,
          inputs:,
          conversation_for_api: api_request_params&.dig(:messages) || [],
          user_id:
        }
        track_ai_generation(
          duration_ms:,
          current_params:,
          request_context:,
          response_data:,
          provider: :gemini
        )
      end

      raise response_data[:error] if response_data[:error]

      response_data[:parsed_json]
    end

    def default_params
      @llm_params
    end

    private

    def normalize_gemini_response!(response_data)
      return unless response_data[:success]
      return unless response_data[:parsed_json].is_a?(Hash)

      parsed = normalize_generate_response(response_data[:parsed_json])

      if !parsed["choices"].is_a?(Array) && parsed["candidates"].is_a?(Array)
        parsed["choices"] = parsed["candidates"].map do |candidate|
          text = candidate.dig("content", "parts", 0, "text")
          {
            "message" => { "role" => "assistant", "content" => text },
            "text" => text,
            "finish_reason" => candidate["finishReason"] || candidate["finish_reason"]
          }
        end
      end

      usage_metadata = parsed["usageMetadata"] || parsed["usage_metadata"]
      if usage_metadata.is_a?(Hash)
        parsed["usage"] ||= {
          "prompt_tokens" => usage_metadata["promptTokenCount"] || usage_metadata["prompt_token_count"],
          "completion_tokens" => usage_metadata["candidatesTokenCount"] || usage_metadata["candidates_token_count"],
          "total_tokens" => usage_metadata["totalTokenCount"] || usage_metadata["total_token_count"]
        }.compact
      end

      response_data[:parsed_json] = parsed
    end
  end
end
