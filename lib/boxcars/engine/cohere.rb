# frozen_string_literal: true

# Boxcars - a framework for running a series of tools to get an answer to a question.
module Boxcars
  # An engine that uses Cohere's API.
  class Cohere < Engine
    include UnifiedObservability
    include OpenAICompatibleChatHelpers

    attr_reader :prompts, :llm_params, :model_kwargs, :batch_size

    # The default parameters to use when asking the engine.
    DEFAULT_PARAMS = {
      model: "command-r-plus",
      max_tokens: 4000,
      max_input_tokens: 1000,
      temperature: 0.2
    }.freeze

    # The default name of the engine.
    DEFAULT_NAME = "Cohere engine"
    # The default description of the engine.
    DEFAULT_DESCRIPTION = "useful for when you need to use Cohere AI to answer questions. " \
                          "You should ask targeted questions"

    # Initializes a Cohere engine instance.
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
      Boxcars::OptionalDependency.require!("faraday", feature: "Boxcars::Cohere")
      ensure_cohere_api_key!(
        cohere_api_key,
        error_class: Boxcars::ConfigurationError,
        message: "Cohere API key not set"
      )

      parse_cohere_response_body(post_cohere_chat(params, cohere_api_key).body)
    end

    # Calls Cohere and returns the parsed response object.
    def client(prompt:, inputs: {}, **kwargs)
      start_time = Time.now
      response_data = { response_obj: nil, parsed_json: nil, success: false, error: nil, status_code: nil }
      current_params = llm_params.merge(kwargs)
      current_prompt_object = normalize_prompt_object(prompt)
      api_request_params = nil

      begin
        api_key = Boxcars.configuration.cohere_api_key(**kwargs)
        api_request_params = current_prompt_object.as_prompt(inputs:, prefixes: default_prefixes,
                                                             show_roles: true).merge(current_params)
        api_request_params[:message] = api_request_params.delete(:prompt)
        api_request_params[:stop_sequences] = api_request_params.delete(:stop) if api_request_params.key?(:stop)

        Boxcars.debug("Prompt after formatting:#{api_request_params[:message]}", :cyan) if Boxcars.configuration.log_prompts

        raw_response = cohere_api_call(api_request_params, api_key)
        process_cohere_response(raw_response, response_data)
      rescue StandardError => e
        handle_cohere_error(e, response_data)
      ensure
        call_context = {
          start_time:,
          prompt_object: current_prompt_object,
          inputs:,
          api_request_params:,
          current_params:
        }
        track_cohere_observability(call_context, response_data)
      end

      cohere_handle_call_outcome(response_data:)
    end

    # Runs the engine and returns the extracted answer text.
    def run(question, **)
      prompt = Prompt.new(template: question)
      response = client(prompt:, **)

      raise Error, "Cohere: No response from API" unless response
      raise Error, "Cohere: #{response['error']}" if response['error']

      answer = extract_answer(response)
      Boxcars.debug("Answer: #{answer}", :cyan)
      answer
    end

    def default_params
      llm_params
    end

    # The engine type.
    def engine_type
      "claude"
    end

    # Looks up the context size for a model by name.
    def modelname_to_contextsize(_modelname)
      100000
    end

    # Calculates the maximum number of tokens possible for a prompt.
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
    def cohere_api_call(params, api_key)
      Boxcars::OptionalDependency.require!("faraday", feature: "Boxcars::Cohere")
      ensure_cohere_api_key!(api_key, error_class: Boxcars::Error, message: "Cohere API key not set")
      post_cohere_chat(params, api_key)
    end

    # Process the raw response from Cohere API
    def process_cohere_response(raw_response, response_data)
      response_data[:response_obj] = raw_response
      response_data[:status_code] = raw_response.status

      if raw_response.status == 200
        parsed_json = JSON.parse(raw_response.body)

        if parsed_json["error"]
          response_data[:success] = false
          response_data[:error] = Boxcars::Error.new("Cohere API Error: #{parsed_json['error']}")
        else
          parsed_json["choices"] ||= if parsed_json["text"]
                                       [{ "text" => parsed_json["text"], "finish_reason" => "stop" }]
                                     else
                                       []
                                     end
          input_tokens = parsed_json.dig("meta", "tokens", "input_tokens") ||
                         parsed_json.dig("meta", "billed_units", "input_tokens")
          output_tokens = parsed_json.dig("meta", "tokens", "output_tokens") ||
                          parsed_json.dig("meta", "billed_units", "output_tokens")
          if input_tokens || output_tokens
            parsed_json["usage"] ||= {
              "prompt_tokens" => input_tokens.to_i,
              "completion_tokens" => output_tokens.to_i,
              "total_tokens" => input_tokens.to_i + output_tokens.to_i
            }
          end
          response_data[:parsed_json] = parsed_json
          response_data[:success] = true
        end
      else
        response_data[:success] = false
        response_data[:error] = Boxcars::Error.new("HTTP #{raw_response.status}: #{raw_response.reason_phrase}")
      end
    end

    # Handle errors from Cohere API calls
    def handle_cohere_error(error, response_data)
      response_data[:error] = error
      response_data[:success] = false
      response_data[:status_code] = openai_compatible_error_status_code(error)
    end

    # Track observability using the unified system
    def track_cohere_observability(call_context, response_data)
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
    def cohere_handle_call_outcome(response_data:)
      if response_data[:error]
        handle_cohere_error_outcome(response_data[:error])
      elsif !response_data[:success]
        handle_cohere_response_body_error(response_data[:response_obj])
      else
        response_data[:parsed_json] # Return the raw parsed JSON
      end
    end

    # Handle error outcomes
    def handle_cohere_error_outcome(error_data)
      detailed_error_message = error_data.message
      if error_data.respond_to?(:response) && error_data.response
        detailed_error_message += " - Details: #{error_data.response[:body]}"
      end
      Boxcars.error("Cohere Error: #{detailed_error_message} (#{error_data.class.name})", :red)
      raise error_data
    end

    # Handle response body errors
    def handle_cohere_response_body_error(response_obj)
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

    def post_cohere_chat(params, api_key)
      cohere_connection(api_key).post { |req| req.body = params.to_json }
    end

    def cohere_connection(api_key)
      Faraday.new('https://api.cohere.ai/v1/chat') do |faraday|
        faraday.request :url_encoded
        faraday.headers['Authorization'] = "Bearer #{api_key}"
        faraday.headers['Content-Type'] = 'application/json'
      end
    end

    def ensure_cohere_api_key!(api_key, error_class:, message:)
      return unless api_key.to_s.strip.empty?

      raise error_class, message
    end

    def parse_cohere_response_body(body)
      JSON.parse(body, symbolize_names: true)
    end
  end
end
