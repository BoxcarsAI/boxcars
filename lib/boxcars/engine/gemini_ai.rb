# frozen_string_literal: true

require 'json'

module Boxcars
  # A engine that uses GeminiAI's API via an OpenAI-compatible interface.
  class GeminiAi < Engine
    include UnifiedObservability
    include OpenAICompatibleChatHelpers

    attr_reader :prompts, :llm_params, :model_kwargs, :batch_size # Corrected typo llm_parmas to llm_params

    DEFAULT_PARAMS = {
      model: "gemini-2.5-flash", # Default model for Gemini
      temperature: 0.1
      # max_tokens is often part of the request, not a fixed default here
    }.freeze
    DEFAULT_NAME = "GeminiAI engine"
    DEFAULT_DESCRIPTION = "useful for when you need to use Gemini AI to answer questions. " \
                          "You should ask targeted questions"

    def initialize(name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, prompts: [], batch_size: 20, **kwargs)
      user_id = kwargs.delete(:user_id)
      @llm_params = DEFAULT_PARAMS.merge(kwargs) # Corrected typo here
      @prompts = prompts
      @batch_size = batch_size
      super(description:, name:, user_id:)
    end

    # Renamed from open_ai_client to gemini_client for clarity
    def self.gemini_client(gemini_api_key: nil)
      access_token = Boxcars.configuration.gemini_api_key(gemini_api_key:)
      Boxcars::OpenAICompatibleClient.build(
        access_token: access_token,
        uri_base: "https://generativelanguage.googleapis.com/v1beta/"
      )
      # Removed /openai from uri_base as it's usually for OpenAI-specific paths on custom domains.
      # The Gemini endpoint might be directly at /v1beta/models/gemini...:generateContent
      # This might need adjustment based on how the OpenAI gem forms the full URL.
      # For direct generateContent, a different client or HTTP call might be needed if OpenAI gem is too restrictive.
      # Assuming for now it's an OpenAI-compatible chat endpoint.
    end

    # Gemini models are typically conversational.
    def conversation_model?(_model_name)
      true
    end

    def client(prompt:, inputs: {}, gemini_api_key: nil, **kwargs)
      start_time = Time.now
      response_data = { response_obj: nil, parsed_json: nil, success: false, error: nil, status_code: nil }
      current_params = @llm_params.merge(kwargs) # Use instance var @llm_params
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
      rescue StandardError => e # Catch other errors
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

      # If there's an error, raise it to maintain backward compatibility with existing tests
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
      @llm_params # Use instance variable
    end

    private

    def gemini_handle_call_outcome(response_data:)
      if response_data[:error]
        Boxcars.error("GeminiAI Error: #{response_data[:error].message} (#{response_data[:error].class.name})", :red)
        raise response_data[:error]
      elsif !response_data[:success]
        err_details = response_data.dig(:response_obj, "error")
        msg = if err_details
                err_details.is_a?(Hash) ? "#{err_details['type']}: #{err_details['message']}" : err_details.to_s
              else
                "Unknown error from GeminiAI API"
              end
        raise Error, msg
      else
        extract_content_from_gemini_response(response_data[:parsed_json])
      end
    end

    def extract_content_from_gemini_response(parsed_json)
      # Handle Gemini's specific response structure (candidates)
      # or OpenAI-compatible structure if the endpoint behaves that way.
      if parsed_json&.key?("candidates") # Native Gemini generateContent response
        parsed_json["candidates"].map { |c| c.dig("content", "parts", 0, "text") }.join("\n").strip
      elsif parsed_json&.key?("choices") # OpenAI-compatible response
        parsed_json["choices"].map { |c| c.dig("message", "content") || c["text"] }.join("\n").strip
      else
        raise Error, "GeminiAI: Could not extract answer from response"
      end
    end

    # validate_response! method uses the base implementation with Gemini-specific must_haves
    def validate_response!(response, must_haves: %w[choices candidates])
      super
    end
  end
end
