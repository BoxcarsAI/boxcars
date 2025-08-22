# frozen_string_literal: true

# Boxcars - a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A engine that uses Cohere's API.
  class Cohere < Engine
    include UnifiedObservability

    attr_reader :prompts, :llm_params, :model_kwargs, :batch_size

    # The default parameters to use when asking the engine.
    DEFAULT_PARAMS = {
      model: "command-r-plus",
      max_tokens: 4000,
      max_input_tokens: 1000,
      temperature: 0.2
    }.freeze

    # the default name of the engine
    DEFAULT_NAME = "Cohere engine"
    # the default description of the engine
    DEFAULT_DESCRIPTION = "useful for when you need to use Cohere AI to answer questions. " \
                          "You should ask targeted questions"

    # A engine is the driver for a single tool to run.
    # @param name [String] The name of the engine. Defaults to "OpenAI engine".
    # @param description [String] A description of the engine. Defaults to:
    #        useful for when you need to use AI to answer questions. You should ask targeted questions".
    # @param prompts [Array<String>] The prompts to use when asking the engine. Defaults to [].
    def initialize(name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, prompts: [], **kwargs)
      user_id = kwargs.delete(:user_id)
      @llm_params = DEFAULT_PARAMS.merge(kwargs)
      @prompts = prompts
      @batch_size = 20
      super(description:, name:, user_id:)
    end

    def conversation_model?(_model)
      true
    end

    def chat(params, cohere_api_key)
      raise Boxcars::ConfigurationError('Cohere API key not set') if cohere_api_key.blank?

      # Define the API endpoint and parameters
      api_endpoint = 'https://api.cohere.ai/v1/chat'

      connection = Faraday.new(api_endpoint) do |faraday|
        faraday.request :url_encoded
        faraday.headers['Authorization'] = "Bearer #{cohere_api_key}"
        faraday.headers['Content-Type'] = 'application/json'
      end

      # Make the API call
      response = connection.post { |req| req.body = params.to_json }
      JSON.parse(response.body, symbolize_names: true)
    end

    # Get an answer from the engine.
    # @param prompt [String] The prompt to use when asking the engine.
    # @param cohere_api_key [String] Optional api key to use when asking the engine.
    #   Defaults to Boxcars.configuration.cohere_api_key.
    # @param kwargs [Hash] Additional parameters to pass to the engine if wanted.
    def client(prompt:, inputs: {}, **kwargs)
      start_time = Time.now
      response_data = { response_obj: nil, parsed_json: nil, success: false, error: nil, status_code: nil }
      current_params = llm_params.merge(kwargs)
      current_prompt_object = prompt.is_a?(Array) ? prompt.first : prompt
      api_request_params = nil

      begin
        api_key = Boxcars.configuration.cohere_api_key(**kwargs)
        api_request_params = current_prompt_object.as_prompt(inputs:, prefixes: default_prefixes,
                                                             show_roles: true).merge(current_params)
        api_request_params[:message] = api_request_params.delete(:prompt)
        api_request_params[:stop_sequences] = api_request_params.delete(:stop) if api_request_params.key?(:stop)

        Boxcars.debug("Prompt after formatting:#{api_request_params[:message]}", :cyan) if Boxcars.configuration.log_prompts

        raw_response = _cohere_api_call(api_request_params, api_key)
        _process_cohere_response(raw_response, response_data)
      rescue StandardError => e
        _handle_cohere_error(e, response_data)
      ensure
        call_context = {
          start_time:,
          prompt_object: current_prompt_object,
          inputs:,
          api_request_params:,
          current_params:
        }
        _track_cohere_observability(call_context, response_data)
      end

      _cohere_handle_call_outcome(response_data:)
    end

    # get an answer from the engine for a question.
    # @param question [String] The question to ask the engine.
    # @param kwargs [Hash] Additional parameters to pass to the engine if wanted.
    def run(question, **)
      prompt = Prompt.new(template: question)
      response = client(prompt:, **)

      raise Error, "Cohere: No response from API" unless response
      raise Error, "Cohere: #{response[:error]}" if response[:error]

      answer = response[:text]
      Boxcars.debug("Answer: #{answer}", :cyan)
      answer
    end

    # Get the default parameters for the engine.
    def default_params
      llm_params
    end

    # validate_response! method uses the base implementation with Cohere-specific must_haves
    def validate_response!(response, must_haves: %w[completion])
      super
    end

    # the engine type
    def engine_type
      "claude"
    end

    # lookup the context size for a model by name
    # @param modelname [String] The name of the model to lookup.
    def modelname_to_contextsize(_modelname)
      100000
    end

    # Calculate the maximum number of tokens possible to generate for a prompt.
    # @param prompt_text [String] The prompt text to use.
    # @return [Integer] the number of tokens possible to generate.
    def max_tokens_for_prompt(prompt_text)
      num_tokens = get_num_tokens(prompt_text)

      # get max context size for model by name
      max_size = modelname_to_contextsize(model_name)
      max_size - num_tokens
    end

    def default_prefixes
      { system: "SYSTEM: ", user: "USER: ", assistant: "CHATBOT: ", history: :history }
    end

    private

    # Make the actual API call to Cohere
    def _cohere_api_call(params, api_key)
      raise Boxcars::Error, 'Cohere API key not set' if api_key.blank?

      # Define the API endpoint and parameters
      api_endpoint = 'https://api.cohere.ai/v1/chat'

      connection = Faraday.new(api_endpoint) do |faraday|
        faraday.request :url_encoded
        faraday.headers['Authorization'] = "Bearer #{api_key}"
        faraday.headers['Content-Type'] = 'application/json'
      end

      # Make the API call
      connection.post { |req| req.body = params.to_json }
    end

    # Process the raw response from Cohere API
    def _process_cohere_response(raw_response, response_data)
      response_data[:response_obj] = raw_response
      response_data[:status_code] = raw_response.status

      if raw_response.status == 200
        parsed_json = JSON.parse(raw_response.body, symbolize_names: true)
        response_data[:parsed_json] = parsed_json

        if parsed_json[:error]
          response_data[:success] = false
          response_data[:error] = Boxcars::Error.new("Cohere API Error: #{parsed_json[:error]}")
        else
          response_data[:success] = true
        end
      else
        response_data[:success] = false
        response_data[:error] = Boxcars::Error.new("HTTP #{raw_response.status}: #{raw_response.reason_phrase}")
      end
    end

    # Handle errors from Cohere API calls
    def _handle_cohere_error(error, response_data)
      response_data[:error] = error
      response_data[:success] = false
      response_data[:status_code] = error.respond_to?(:response) && error.response ? error.response[:status] : nil
    end

    # Track observability using the unified system
    def _track_cohere_observability(call_context, response_data)
      duration_ms = ((Time.now - call_context[:start_time]) * 1000).round
      request_context = {
        prompt: call_context[:prompt_object],
        inputs: call_context[:inputs],
        conversation_for_api: call_context[:api_request_params],
        user_id:
      }

      track_ai_generation(
        duration_ms:,
        current_params: call_context[:current_params],
        request_context:,
        response_data:,
        provider: :cohere
      )
    end

    # Handle the final outcome of the API call
    def _cohere_handle_call_outcome(response_data:)
      if response_data[:error]
        _handle_cohere_error_outcome(response_data[:error])
      elsif !response_data[:success]
        _handle_cohere_response_body_error(response_data[:response_obj])
      else
        response_data[:parsed_json] # Return the raw parsed JSON
      end
    end

    # Handle error outcomes
    def _handle_cohere_error_outcome(error_data)
      detailed_error_message = error_data.message
      if error_data.respond_to?(:response) && error_data.response
        detailed_error_message += " - Details: #{error_data.response[:body]}"
      end
      Boxcars.error("Cohere Error: #{detailed_error_message} (#{error_data.class.name})", :red)
      raise error_data
    end

    # Handle response body errors
    def _handle_cohere_response_body_error(response_obj)
      msg = "Unknown error from Cohere API"
      if response_obj.respond_to?(:body)
        begin
          parsed_body = JSON.parse(response_obj.body)
          msg = parsed_body["message"] || parsed_body["error"] || msg
        rescue JSON::ParserError
          msg = "HTTP #{response_obj.status}: #{response_obj.reason_phrase}"
        end
      end
      raise Error, msg
    end
  end
end
