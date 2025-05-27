# frozen_string_literal: true

require 'openai'
require 'json'
require_relative 'openai_observability'

module Boxcars
  # A engine that uses OpenAI's API.
  class Openai < Engine
    include OpenAIObservability
    attr_reader :prompts, :open_ai_params, :model_kwargs, :batch_size

    DEFAULT_PARAMS = {
      model: "gpt-4o-mini",
      temperature: 0.1,
      max_tokens: 4096
    }.freeze
    DEFAULT_NAME = "OpenAI engine"
    DEFAULT_DESCRIPTION = "useful for when you need to use AI to answer questions. " \
                          "You should ask targeted questions"

    def initialize(name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, prompts: [], batch_size: 20, **kwargs)
      @open_ai_params = DEFAULT_PARAMS.merge(kwargs)
      # Special handling for o1-mini model (deprecated?)
      if @open_ai_params[:model] =~ /^o/ && @open_ai_params[:max_tokens].present?
        @open_ai_params[:max_completion_tokens] = @open_ai_params.delete(:max_tokens)
        @open_ai_params.delete(:temperature) # o1-mini might not support temperature
      end

      @prompts = prompts
      @batch_size = batch_size
      super(description: description, name: name)
    end

    def self.open_ai_client(openai_access_token: nil)
      access_token = Boxcars.configuration.openai_access_token(openai_access_token: openai_access_token)
      organization_id = Boxcars.configuration.organization_id
      # log_errors is good for the gem's own logging
      ::OpenAI::Client.new(access_token: access_token, organization_id: organization_id, log_errors: true)
    end

    def conversation_model?(model_name)
      !!(model_name =~ /(^gpt-4)|(-turbo\b)|(^o\d)|(gpt-3\.5-turbo)/) # Added gpt-3.5-turbo
    end

    def _prepare_openai_chat_request(prompt_object, inputs, current_params)
      get_params(prompt_object, inputs, current_params.dup)
    end

    def _prepare_openai_completion_request(prompt_object, inputs, current_params)
      prompt_text_for_api = prompt_object.as_prompt(inputs: inputs)
      prompt_text_for_api = prompt_text_for_api[:prompt] if prompt_text_for_api.is_a?(Hash) && prompt_text_for_api.key?(:prompt)
      { prompt: prompt_text_for_api }.merge(current_params).tap { |p| p.delete(:messages) }
    end

    def _execute_openai_api_call(client, is_chat_model, api_request_params)
      if is_chat_model
        log_messages_debug(api_request_params[:messages]) if Boxcars.configuration.log_prompts && api_request_params[:messages]
        client.chat(parameters: api_request_params)
      else
        Boxcars.debug("Prompt after formatting:\n#{api_request_params[:prompt]}", :cyan) if Boxcars.configuration.log_prompts
        client.completions(parameters: api_request_params)
      end
    end

    def _process_openai_response(raw_response, response_data)
      response_data[:response_obj] = raw_response
      response_data[:parsed_json] = raw_response # Already parsed by OpenAI gem

      if raw_response && !raw_response["error"]
        response_data[:success] = true
        response_data[:status_code] = 200 # Inferred
      else
        response_data[:success] = false
        err_details = raw_response["error"] if raw_response
        msg = err_details ? "#{err_details['type']}: #{err_details['message']}" : "Unknown OpenAI API Error"
        response_data[:error] ||= StandardError.new(msg) # Use ||= to not overwrite existing exception
      end
    end

    def _handle_openai_api_error(error, response_data)
      response_data[:error] = error
      response_data[:success] = false
      response_data[:status_code] = error.http_status if error.respond_to?(:http_status)
    end

    def _handle_openai_standard_error(error, response_data)
      response_data[:error] = error
      response_data[:success] = false
    end

    def client(prompt:, inputs: {}, openai_access_token: nil, **kwargs)
      start_time = Time.now
      response_data = { response_obj: nil, parsed_json: nil, success: false, error: nil, status_code: nil }
      current_params = open_ai_params.merge(kwargs)
      current_prompt_object = prompt.is_a?(Array) ? prompt.first : prompt
      api_request_params = nil
      is_chat_model = conversation_model?(current_params[:model])

      begin
        clnt = Openai.open_ai_client(openai_access_token: openai_access_token)
        api_request_params = if is_chat_model
                               _prepare_openai_chat_request(current_prompt_object, inputs, current_params)
                             else
                               _prepare_openai_completion_request(current_prompt_object, inputs, current_params)
                             end
        raw_response = _execute_openai_api_call(clnt, is_chat_model, api_request_params)
        _process_openai_response(raw_response, response_data)
      rescue ::OpenAI::Error => e
        _handle_openai_api_error(e, response_data)
      rescue StandardError => e
        _handle_openai_standard_error(e, response_data)
      ensure
        call_context = {
          start_time: start_time,
          prompt_object: current_prompt_object,
          inputs: inputs,
          api_request_params: api_request_params,
          current_params: current_params,
          is_chat_model: is_chat_model
        }
        _track_openai_observability(call_context, response_data)
      end

      _openai_handle_call_outcome(response_data: response_data)
    end

    # Called by Engine#generate to check the response from the client.
    # @param response [Hash] The parsed JSON response from the OpenAI API.
    # @raise [Boxcars::Error] if the response contains an error.
    def check_response(response)
      if response.is_a?(Hash) && response["error"]
        err_details = response["error"]
        msg = err_details ? "#{err_details['type']}: #{err_details['message']}" : "Unknown OpenAI API Error in check_response"
        raise Boxcars::Error, msg
      end
      true
    end

    def run(question, **kwargs)
      prompt = Prompt.new(template: question)
      # client now returns the raw JSON response. We need to extract the answer.
      raw_response = client(prompt: prompt, inputs: {}, **kwargs)
      answer = _extract_openai_answer_from_choices(raw_response["choices"])
      Boxcars.debug("Answer: #{answer}", :cyan)
      answer
    end

    def default_params
      open_ai_params
    end

    private

    def log_messages_debug(messages)
      return unless messages.is_a?(Array)

      Boxcars.debug(messages.last(2).map { |p| ">>>>>> Role: #{p[:role]} <<<<<<\n#{p[:content]}" }.join("\n"), :cyan)
    end

    def get_params(prompt_object, inputs, params)
      # Ensure prompt_object is a Boxcars::Prompt
      current_prompt_object = if prompt_object.is_a?(Boxcars::Prompt)
                                prompt_object
                              else
                                Boxcars::Prompt.new(template: prompt_object.to_s)
                              end

      # Use as_messages for chat models
      formatted_params = current_prompt_object.as_messages(inputs).merge(params)

      # Handle models like o1-mini that don't support the system role
      if formatted_params[:model] =~ /^o/ && formatted_params[:messages].first&.fetch(:role)&.to_s == 'system'
        formatted_params[:messages].first[:role] = :user
      end
      # o1-mini specific param adjustments (already in initialize, but good to ensure here if params are rebuilt)
      if formatted_params[:model] =~ /^o/
        formatted_params.delete(:response_format)
        formatted_params.delete(:stop)
        if formatted_params.key?(:max_tokens) && !formatted_params.key?(:max_completion_tokens)
          formatted_params[:max_completion_tokens] = formatted_params.delete(:max_tokens)
        end
        formatted_params.delete(:temperature)
      end
      formatted_params
    end

    def _handle_openai_error_outcome(error_data)
      detailed_error_message = error_data.message
      if error_data.respond_to?(:json_body) && error_data.json_body
        detailed_error_message += " - Details: #{error_data.json_body}"
      end
      Boxcars.error("OpenAI Error: #{detailed_error_message} (#{error_data.class.name})", :red)
      raise error_data
    end

    def _handle_openai_response_body_error(response_obj)
      err_details = response_obj&.dig("error")
      msg = err_details ? "#{err_details['type']}: #{err_details['message']}" : "Unknown error from OpenAI API"
      raise Error, msg
    end

    def _extract_openai_answer_from_choices(choices)
      raise Error, "OpenAI: No choices found in response" unless choices.is_a?(Array) && !choices.empty?

      if choices.first&.dig("message", "content")
        choices.map { |c| c.dig("message", "content") }.join("\n").strip
      elsif choices.first&.dig("text")
        choices.map { |c| c["text"] }.join("\n").strip
      else
        raise Error, "OpenAI: Could not extract answer from choices"
      end
    end

    def _openai_handle_call_outcome(response_data:)
      if response_data[:error]
        _handle_openai_error_outcome(response_data[:error])
      elsif !response_data[:success] # e.g. raw_response["error"] was present
        _handle_openai_response_body_error(response_data[:response_obj]) # Raises an error
      else
        response_data[:parsed_json] # Return the raw parsed JSON for Engine#generate
      end
    end
  end
end
