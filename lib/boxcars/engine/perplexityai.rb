# frozen_string_literal: true

require 'faraday'
require 'faraday/retry'
require 'json'

module Boxcars
  # A engine that uses PerplexityAI's API.
  class Perplexityai < Engine
    include UnifiedObservability
    attr_reader :prompts, :perplexity_params, :model_kwargs, :batch_size

    DEFAULT_PARAMS = { # Renamed from DEFAULT_PER_PARAMS for consistency
      model: "llama-3-sonar-large-32k-online", # Removed extra quotes
      temperature: 0.1
      # max_tokens can be part of kwargs if needed
    }.freeze
    DEFAULT_NAME = "PerplexityAI engine" # Renamed from DEFAULT_PER_NAME
    DEFAULT_DESCRIPTION = "useful for when you need to use Perplexity AI to answer questions. " \
                          "You should ask targeted questions"

    def initialize(name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, prompts: [], batch_size: 20, **kwargs)
      @perplexity_params = DEFAULT_PARAMS.merge(kwargs)
      @prompts = prompts
      @batch_size = batch_size # Retain if used by generate
      super(description: description, name: name)
    end

    # Perplexity models are conversational.
    def conversation_model?(_model_name)
      true
    end

    # Main client method for interacting with the Perplexity API
    # rubocop:disable Metrics/MethodLength
    def client(prompt:, inputs: {}, perplexity_api_key: nil, **kwargs)
      start_time = Time.now
      response_data = { response_obj: nil, parsed_json: nil, success: false, error: nil, status_code: nil }
      current_params = @perplexity_params.merge(kwargs)
      api_request_params = nil # Parameters actually sent to Perplexity API
      current_prompt_object = prompt.is_a?(Array) ? prompt.first : prompt

      begin
        api_key = perplexity_api_key || Boxcars.configuration.perplexity_api_key(**current_params.slice(:perplexity_api_key))
        raise Boxcars::ConfigurationError, "Perplexity API key not set" if api_key.nil? || api_key.strip.empty?

        conn = Faraday.new(url: "https://api.perplexity.ai") do |faraday|
          faraday.request :json
          faraday.response :json # Parse JSON response
          faraday.response :raise_error # Raise exceptions on 4xx/5xx
          faraday.adapter Faraday.default_adapter
        end

        messages_for_api = current_prompt_object.as_messages(inputs)[:messages]
        # Perplexity expects a 'model' and 'messages' structure.
        # Other params like temperature, max_tokens are top-level.
        api_request_params = {
          model: current_params[:model],
          messages: messages_for_api
        }.merge(current_params.except(:model, :messages, :perplexity_api_key)) # Add other relevant params

        log_messages_debug(api_request_params[:messages]) if Boxcars.configuration.log_prompts && api_request_params[:messages]

        response = conn.post('/chat/completions') do |req|
          req.headers['Authorization'] = "Bearer #{api_key}"
          req.body = api_request_params
        end

        response_data[:response_obj] = response # Faraday response object
        response_data[:parsed_json] = response.body # Faraday with :json middleware parses body
        response_data[:status_code] = response.status

        if response.success? && response.body && response.body["choices"]
          response_data[:success] = true
        else
          response_data[:success] = false
          err_details = response.body["error"] if response.body.is_a?(Hash)
          msg = if err_details
                  "#{err_details['type']}: #{err_details['message']}"
                else
                  "Unknown Perplexity API Error (status: #{response.status})"
                end
          response_data[:error] = StandardError.new(msg)
        end
      rescue Faraday::Error => e # Catch Faraday specific errors (includes connection, timeout, 4xx/5xx)
        response_data[:error] = e
        response_data[:success] = false
        response_data[:status_code] = e.response_status if e.respond_to?(:response_status)
        response_data[:response_obj] = e.response if e.respond_to?(:response) # Store Faraday response if available
        response_data[:parsed_json] = e.response[:body] if e.respond_to?(:response) && e.response[:body].is_a?(Hash)
      rescue StandardError => e # Catch other unexpected errors
        response_data[:error] = e
        response_data[:success] = false
      ensure
        duration_ms = ((Time.now - start_time) * 1000).round
        request_context = {
          prompt: current_prompt_object,
          inputs: inputs,
          conversation_for_api: api_request_params&.dig(:messages)
        }
        track_ai_generation(
          duration_ms: duration_ms,
          current_params: current_params,
          request_context: request_context,
          response_data: response_data,
          provider: :perplexity_ai
        )
      end

      _perplexity_handle_call_outcome(response_data: response_data)
    end
    # rubocop:enable Metrics/MethodLength

    def run(question, **)
      prompt = Prompt.new(template: question)
      answer = client(prompt: prompt, inputs: {}, **)
      Boxcars.debug("Answer: #{answer}", :cyan)
      answer
    end

    def default_params
      @perplexity_params
    end

    private

    def log_messages_debug(messages)
      return unless messages.is_a?(Array)

      Boxcars.debug(messages.last(2).map { |p| ">>>>>> Role: #{p[:role]} <<<<<<\n#{p[:content]}" }.join("\n"), :cyan)
    end

    def _perplexity_handle_call_outcome(response_data:)
      if response_data[:error]
        Boxcars.error("PerplexityAI Error: #{response_data[:error].message} (#{response_data[:error].class.name})", :red)
        raise response_data[:error]
      elsif !response_data[:success]
        err_details = response_data.dig(:parsed_json, "error")
        msg = err_details ? "#{err_details['type']}: #{err_details['message']}" : "Unknown error from PerplexityAI API"
        raise Error, msg
      else
        choices = response_data.dig(:parsed_json, "choices")
        raise Error, "PerplexityAI: No choices found in response" unless choices.is_a?(Array) && !choices.empty?

        choices.map { |c| c.dig("message", "content") }.join("\n").strip
      end
    end

    # Methods like `check_response`, `generate`, `generation_info` are removed or would need significant rework.
    # `check_response` logic is now part of `_perplexity_handle_call_outcome`.
    # `generate` would need to be re-implemented carefully if batching is desired with direct Faraday.
  end
end
