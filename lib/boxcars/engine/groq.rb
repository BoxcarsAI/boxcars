# frozen_string_literal: true

require 'openai' # Groq uses the OpenAI gem with a custom URI base
require 'json'

module Boxcars
  # A engine that uses Groq's API.
  class Groq < Engine
    attr_reader :prompts, :groq_params, :model_kwargs, :batch_size

    DEFAULT_PARAMS = {
      model: "llama3-70b-8192",
      temperature: 0.1,
      max_tokens: 4096 # Groq API might have specific limits or naming for this
    }.freeze
    DEFAULT_NAME = "Groq engine"
    DEFAULT_DESCRIPTION = "useful for when you need to use Groq AI to answer questions. " \
                          "You should ask targeted questions"

    def initialize(name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, prompts: [], batch_size: 20, **kwargs)
      @groq_params = DEFAULT_PARAMS.merge(kwargs) # Corrected typo here
      @prompts = prompts
      @batch_size = batch_size
      super(description: description, name: name)
    end

    # Renamed from open_ai_client to groq_client for clarity
    def self.groq_client(groq_api_key: nil)
      access_token = Boxcars.configuration.groq_api_key(groq_api_key: groq_api_key)
      ::OpenAI::Client.new(access_token: access_token, uri_base: "https://api.groq.com/openai/v1")
      # Adjusted uri_base to include /v1 as is common for OpenAI-compatible APIs
    end

    # Groq models are typically conversational.
    def conversation_model?(_model_name)
      true
    end

    def client(prompt:, inputs: {}, groq_api_key: nil, **kwargs)
      start_time = Time.now
      response_data = { response_obj: nil, parsed_json: nil, success: false, error: nil, status_code: nil }
      current_params = @groq_params.merge(kwargs)
      current_prompt_object = prompt.is_a?(Array) ? prompt.first : prompt
      api_request_params = nil # Initialize

      begin
        clnt = Groq.groq_client(groq_api_key: groq_api_key)
        api_request_params = _prepare_groq_request_params(current_prompt_object, inputs, current_params)

        log_messages_debug(api_request_params[:messages]) if Boxcars.configuration.log_prompts && api_request_params[:messages]

        _execute_and_process_groq_call(clnt, api_request_params, response_data)
      rescue ::OpenAI::Error => e
        _handle_openai_error_for_groq(e, response_data)
      rescue StandardError => e
        _handle_standard_error_for_groq(e, response_data)
      ensure
        _track_groq_observability(start_time, current_prompt_object, inputs, api_request_params, current_params, response_data)
      end

      _groq_handle_call_outcome(response_data: response_data)
    end

    def run(question, **)
      prompt = Prompt.new(template: question)
      answer = client(prompt: prompt, inputs: {}, **)
      Boxcars.debug("Answer: #{answer}", :cyan)
      answer
    end

    def default_params
      @groq_params # Use instance variable
    end

    private

    # Helper methods for the client method
    def _prepare_groq_request_params(prompt_object, inputs, current_params)
      messages_hash_from_prompt = prompt_object.as_messages(inputs)
      actual_messages_for_api = messages_hash_from_prompt[:messages]
      { messages: actual_messages_for_api }.merge(current_params)
    end

    def _execute_and_process_groq_call(clnt, api_request_params, response_data)
      raw_response = clnt.chat(parameters: api_request_params)
      response_data[:response_obj] = raw_response
      response_data[:parsed_json] = raw_response # OpenAI gem returns Hash

      if raw_response && !raw_response["error"] && raw_response["choices"]
        response_data[:success] = true
        response_data[:status_code] = 200 # Inferred
      else
        response_data[:success] = false
        err_details = raw_response["error"] if raw_response
        msg = if err_details
                (err_details.is_a?(Hash) ? err_details['message'] : err_details).to_s
              else
                "Unknown Groq API Error"
              end
        response_data[:error] ||= StandardError.new(msg) # Use ||= to not overwrite existing exception
      end
    end

    def _handle_openai_error_for_groq(error, response_data)
      response_data[:error] = error
      response_data[:success] = false
      response_data[:status_code] = error.http_status if error.respond_to?(:http_status)
    end

    def _handle_standard_error_for_groq(error, response_data)
      response_data[:error] = error
      response_data[:success] = false
    end

    def _track_groq_observability(start_time, prompt_object, inputs, api_request_params, current_params, response_data)
      duration_ms = ((Time.now - start_time) * 1000).round
      request_context = {
        prompt: prompt_object,
        inputs: inputs,
        conversation_for_api: api_request_params&.dig(:messages)
      }

      properties = _groq_build_observability_properties(
        duration_ms: duration_ms,
        current_params: current_params,
        api_request_params: api_request_params,
        request_context: request_context,
        response_data: response_data
      )
      Boxcars::Observability.track(event: 'llm_call', properties: properties.compact)
    end

    # Helper methods for _groq_extract_error_details
    def _extract_openai_error_details_for_groq(error, properties)
      properties[:error_type] = error.type if error.respond_to?(:type)
      properties[:error_code] = error.code if error.respond_to?(:code)
      properties[:status_code] ||= error.http_status if error.respond_to?(:http_status)
    end

    def _is_groq_api_error_response?(response_data)
      !response_data[:success] && response_data[:response_obj] && response_data[:response_obj]["error"]
    end

    def _extract_groq_api_error_details(err_details, properties)
      if err_details.is_a?(Hash)
        properties[:error_message] ||= err_details['message']
        properties[:error_type] ||= err_details['type']
        properties[:error_code] ||= err_details['code']
      else
        properties[:error_message] ||= err_details.to_s
      end
      properties[:error_class] ||= "Boxcars::Error"
    end

    def log_messages_debug(messages)
      return unless messages.is_a?(Array)

      Boxcars.debug(messages.last(2).map { |p| ">>>>>> Role: #{p[:role]} <<<<<<\n#{p[:content]}" }.join("\n"), :cyan)
    end

    def _groq_extract_error_details(response_data:, properties:)
      error = response_data[:error]
      return unless error

      properties[:error_message] = error.message
      properties[:error_class] = error.class.name
      properties[:error_backtrace] = error.backtrace&.join("\n")

      if error.is_a?(::OpenAI::Error)
        _extract_openai_error_details_for_groq(error, properties)
      elsif _is_groq_api_error_response?(response_data)
        err_details = response_data[:response_obj]["error"]
        _extract_groq_api_error_details(err_details, properties)
      end
    end

    def _groq_build_observability_properties(duration_ms:, current_params:, api_request_params:, request_context:, response_data:)
      properties = {
        provider: :groq, # Specific provider name
        model_name: api_request_params&.dig(:model) || current_params[:model],
        prompt_content: request_context[:conversation_for_api],
        inputs: request_context[:inputs],
        api_call_parameters: current_params,
        duration_ms: duration_ms,
        success: response_data[:success]
      }.merge(_groq_extract_response_properties(response_data))

      _groq_extract_error_details(response_data: response_data, properties: properties)
      properties
    end

    def _groq_extract_response_properties(response_data)
      raw_response_body = response_data[:response_obj]
      parsed_response_body = response_data[:success] ? raw_response_body : nil
      status_code = response_data[:status_code]

      {
        response_raw_body: raw_response_body ? JSON.pretty_generate(raw_response_body) : nil,
        response_parsed_body: parsed_response_body,
        status_code: status_code
      }
    end

    def _groq_handle_call_outcome(response_data:)
      if response_data[:error]
        Boxcars.error("Groq Error: #{response_data[:error].message} (#{response_data[:error].class.name})", :red)
        raise response_data[:error]
      elsif !response_data[:success]
        err_details = response_data.dig(:response_obj, "error")
        msg = if err_details
                err_details.is_a?(Hash) ? "#{err_details['type']}: #{err_details['message']}" : err_details.to_s
              else
                "Unknown error from Groq API"
              end
        raise Error, msg
      else
        choices = response_data.dig(:parsed_json, "choices")
        raise Error, "Groq: No choices found in response" unless choices.is_a?(Array) && !choices.empty?

        choices.map { |c| c.dig("message", "content") || c["text"] }.join("\n").strip
      end
    end

    # Retaining check_response if run method or other parts still use it.
    def check_response(response, must_haves: %w[choices])
      if response['error'].is_a?(Hash)
        code = response.dig('error', 'code')
        msg = response.dig('error', 'message') || 'unknown error'
        # GROQ_API_TOKEN is not standard, usually it's an API key.
        raise KeyError, "Groq API Key not valid or permission issue" if ['invalid_api_key', 'permission_denied'].include?(code)

        raise ValueError, "Groq error: #{msg}"
      end

      must_haves.each do |key|
        raise ValueError, "Expecting key #{key} in response" unless response.key?(key) && !response[key].empty?
      end
    end
  end
end
