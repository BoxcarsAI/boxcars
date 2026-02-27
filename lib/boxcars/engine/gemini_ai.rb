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

    def conversation_model?(_model_name)
      true
    end

    def client(prompt:, inputs: {}, gemini_api_key: nil, **kwargs)
      start_time = Time.now
      response_data = { response_obj: nil, parsed_json: nil, success: false, error: nil, status_code: nil }
      current_params = @llm_params.merge(kwargs)
      api_request_params = nil
      current_prompt_object = prompt.is_a?(Array) ? prompt.first : prompt

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

    def run(question, **)
      prompt = Prompt.new(template: question)
      response = client(prompt:, inputs: {}, **)
      answer = extract_content_from_gemini_response(response)
      Boxcars.debug("Answer: #{answer}", :cyan)
      answer
    end

    def default_params
      @llm_params
    end

    private

    def extract_content_from_gemini_response(parsed_json)
      if parsed_json&.key?("candidates")
        parsed_json["candidates"].map { |c| c.dig("content", "parts", 0, "text") }.join("\n").strip
      elsif parsed_json&.key?("choices")
        parsed_json["choices"].map { |c| c.dig("message", "content") || c["text"] }.join("\n").strip
      else
        raise Error, "GeminiAI: Could not extract answer from response"
      end
    end

    def validate_response!(response, must_haves: %w[choices candidates])
      super
    end
  end
end
