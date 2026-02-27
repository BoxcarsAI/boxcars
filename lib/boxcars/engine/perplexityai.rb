# frozen_string_literal: true

require 'json'

module Boxcars
  # An engine that uses PerplexityAI's API.
  class Perplexityai < Engine
    include UnifiedObservability
    include OpenAICompatibleChatHelpers

    attr_reader :prompts, :perplexity_params, :model_kwargs, :batch_size

    DEFAULT_PARAMS = {
      model: "llama-3-sonar-large-32k-online",
      temperature: 0.1
    }.freeze
    DEFAULT_NAME = "PerplexityAI engine"
    DEFAULT_DESCRIPTION = "useful for when you need to use Perplexity AI to answer questions. " \
                          "You should ask targeted questions"

    def initialize(name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, prompts: [], batch_size: 20, **kwargs)
      user_id = kwargs.delete(:user_id)
      @perplexity_params = DEFAULT_PARAMS.merge(kwargs)
      @prompts = prompts
      @batch_size = batch_size
      super(description:, name:, user_id:)
    end

    # rubocop:disable Metrics/MethodLength
    def client(prompt:, inputs: {}, perplexity_api_key: nil, **kwargs)
      start_time = Time.now
      response_data = { response_obj: nil, parsed_json: nil, success: false, error: nil, status_code: nil }
      current_params = @perplexity_params.merge(kwargs)
      api_request_params = nil
      current_prompt_object = prompt

      begin
        Boxcars::OptionalDependency.require!("faraday", feature: "Boxcars::Perplexityai")
        api_key = perplexity_api_key || Boxcars.configuration.perplexity_api_key(**current_params.slice(:perplexity_api_key))
        raise Boxcars::ConfigurationError, "Perplexity API key not set" if api_key.nil? || api_key.strip.empty?

        conn = Faraday.new(url: "https://api.perplexity.ai") do |faraday|
          faraday.request :json
          faraday.response :json
          faraday.response :raise_error
          faraday.adapter Faraday.default_adapter
        end

        messages_for_api = current_prompt_object.as_messages(inputs)[:messages]
        supported_params = filter_supported_params(current_params)
        api_request_params = {
          model: supported_params[:model],
          messages: messages_for_api
        }.merge(supported_params.except(:model, :messages, :perplexity_api_key))

        log_messages_debug(api_request_params[:messages]) if Boxcars.configuration.log_prompts && api_request_params[:messages]

        response = conn.post('/chat/completions') do |req|
          req.headers['Authorization'] = "Bearer #{api_key}"
          req.body = api_request_params
        end

        parsed_json = normalize_generate_response(response.body)
        response_data[:response_obj] = response
        response_data[:parsed_json] = parsed_json
        response_data[:status_code] = response.status

        if response.success? && parsed_json["choices"]
          response_data[:success] = true
        else
          response_data[:success] = false
          err_details = parsed_json["error"] if parsed_json.is_a?(Hash)
          msg = if err_details
                  "#{err_details['type']}: #{err_details['message']}"
                else
                  "Unknown Perplexity API Error (status: #{response.status})"
                end
          response_data[:error] = StandardError.new(msg)
        end
      rescue StandardError => e
        handle_openai_compatible_standard_error(e, response_data)
        if defined?(Faraday::Error) && e.is_a?(Faraday::Error)
          response_data[:status_code] = e.response_status if e.respond_to?(:response_status)
          response_data[:response_obj] = e.response if e.respond_to?(:response)
          if e.respond_to?(:response) && e.response[:body].is_a?(Hash)
            response_data[:parsed_json] = normalize_generate_response(e.response[:body])
          end
        end
      ensure
        duration_ms = ((Time.now - start_time) * 1000).round
        request_context = {
          prompt: current_prompt_object,
          inputs:,
          user_id:,
          conversation_for_api: api_request_params&.dig(:messages)
        }
        track_ai_generation(
          duration_ms:,
          current_params:,
          request_context:,
          response_data:,
          provider: :perplexity_ai
        )
      end

      perplexity_handle_call_outcome(response_data:)
    end
    # rubocop:enable Metrics/MethodLength

    def default_params
      @perplexity_params
    end

    private

    def filter_supported_params(params)
      supported_keys = %i[
        model
        messages
        temperature
        max_tokens
        top_p
        top_k
        stream
        presence_penalty
        frequency_penalty
      ]

      params.select { |key, _| supported_keys.include?(key.to_sym) }
    end

    def perplexity_handle_call_outcome(response_data:)
      if response_data[:error]
        Boxcars.error("PerplexityAI Error: #{response_data[:error].message} (#{response_data[:error].class.name})", :red)
        raise response_data[:error]
      elsif !response_data[:success]
        err_details = response_data.dig(:parsed_json, "error")
        msg = err_details ? "#{err_details['type']}: #{err_details['message']}" : "Unknown error from PerplexityAI API"
        raise Error, msg
      else
        parsed_response = response_data[:parsed_json]
        unless parsed_response["choices"].is_a?(Array) && !parsed_response["choices"].empty?
          raise Error,
                "PerplexityAI: No choices found in response"
        end

        parsed_response
      end
    end
  end
end
