# frozen_string_literal: true

require 'gpt4all'
require 'json' # For pretty_generate

module Boxcars
  # A engine that uses local GPT4All API.
  # Stays inheriting from Engine
  class Gpt4allEng < Engine
    attr_reader :prompts, :model_kwargs, :batch_size, :gpt4all_params # Added gpt4all_params

    DEFAULT_NAME = "Gpt4all engine"
    DEFAULT_DESCRIPTION = "useful for when you need to use local AI to answer questions. " \
                          "You should ask targeted questions"
    # GPT4All doesn't have typical API params like temperature or model selection via params in the same way.
    # Model is usually pre-loaded. We can add a placeholder for model_name if needed for tracking.
    DEFAULT_PARAMS = {
      model_name: "gpt4all-j-v1.3-groovy" # Example, actual model depends on local setup
    }.freeze

    def initialize(name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, prompts: [], batch_size: 2, **kwargs)
      @gpt4all_params = DEFAULT_PARAMS.merge(kwargs) # Store merged params
      @prompts = prompts
      @batch_size = batch_size # Retain if used by other methods
      super(description: description, name: name)
    end

    def client(prompt:, inputs: {}, **kwargs)
      start_time = Time.now
      response_data = { response_obj: nil, parsed_json: nil, success: false, error: nil, status_code: nil }
      # current_params are the effective parameters for this call, including defaults and overrides
      current_params = @gpt4all_params.merge(kwargs)
      # api_request_params for GPT4All is just the input text.
      api_request_params = nil
      current_prompt_object = prompt.is_a?(Array) ? prompt.first : prompt
      gpt4all_instance = nil # To ensure it's in scope for ensure block

      begin
        gpt4all_instance = Gpt4all::ConversationalAI.new
        # prepare_resources might download models, could take time.
        # Consider if this setup should be outside the timed/tracked client call for long-running setup.
        # For now, including it as it's part of the interaction.
        gpt4all_instance.prepare_resources(force_download: false)
        gpt4all_instance.start_bot

        # GPT4All gem's prompt method takes a string.
        prompt_text_for_api = current_prompt_object.as_prompt(inputs: inputs)
        prompt_text_for_api = prompt_text_for_api[:prompt] if prompt_text_for_api.is_a?(Hash) && prompt_text_for_api.key?(:prompt)
        api_request_params = { prompt: prompt_text_for_api } # Store what's sent

        Boxcars.debug("Prompt after formatting:\n#{prompt_text_for_api}", :cyan) if Boxcars.configuration.log_prompts

        raw_response_text = gpt4all_instance.prompt(prompt_text_for_api) # Actual call

        # GPT4All gem returns a string directly, or raises error.
        response_data[:response_obj] = raw_response_text # Store the raw string
        response_data[:parsed_json] = { "text" => raw_response_text } # Create a simple hash for consistency
        response_data[:success] = true
        response_data[:status_code] = 200 # Inferred for local success
      rescue StandardError => e
        response_data[:error] = e
        response_data[:success] = false
        # No HTTP status code for local errors typically, unless the gem provides one.
      ensure
        gpt4all_instance&.stop_bot # Ensure bot is stopped even if errors occur

        duration_ms = ((Time.now - start_time) * 1000).round
        request_context = {
          prompt: current_prompt_object,
          inputs: inputs,
          conversation_for_api: api_request_params&.dig(:prompt) # The text prompt
        }

        properties = _gpt4all_build_observability_properties(
          duration_ms: duration_ms,
          current_params: current_params, # User-intended and default params
          api_request_params: api_request_params, # Actual params sent (the prompt text)
          request_context: request_context,
          response_data: response_data
        )
        Boxcars::Observability.track(event: 'llm_call', properties: properties.compact)
      end

      _gpt4all_handle_call_outcome(response_data: response_data)
    end

    def run(question, **kwargs)
      prompt = Prompt.new(template: question)
      answer = client(prompt: prompt, inputs: {}, **kwargs)
      Boxcars.debug("Answer: #{answer}", :cyan)
      answer
    end

    # Added for consistency
    def default_params
      @gpt4all_params
    end

    private

    def _gpt4all_extract_error_details(response_data:, properties:)
      error = response_data[:error]
      return unless error

      properties[:error_message] = error.message
      properties[:error_class] = error.class.name
      properties[:error_backtrace] = error.backtrace&.join("\n")
      # No specific error types or codes from the gpt4all gem are typically exposed beyond StandardError.
    end

    def _gpt4all_build_observability_properties(duration_ms:, current_params:, api_request_params:, request_context:,
                                                response_data:)
      properties = {
        provider: :gpt4all, # Specific provider name
        model_name: current_params[:model_name], # From DEFAULT_PARAMS or overridden
        prompt_content: [{ role: "user", content: request_context[:conversation_for_api] }], # GPT4All is a direct prompt
        inputs: request_context[:inputs],
        # Log relevant params, like prompt_length, excluding model_name which is already a top-level property
        api_call_parameters: current_params.except(:model_name).merge(prompt_length: api_request_params&.dig(:prompt)&.length),
        duration_ms: duration_ms,
        success: response_data[:success]
      }.merge(_gpt4all_extract_response_properties(response_data))

      _gpt4all_extract_error_details(response_data: response_data, properties: properties)
      properties
    end

    def _gpt4all_extract_response_properties(response_data)
      raw_response_text = response_data[:response_obj] # String
      parsed_response_hash = response_data[:parsed_json] # Hash like {"text": "..."}

      {
        # For gpt4all, raw_body and parsed_body might be similar if we consider the string as raw.
        # Storing the hash version in parsed_body for consistency with other LLMs.
        response_raw_body: raw_response_text,
        response_parsed_body: response_data[:success] ? parsed_response_hash : nil,
        status_code: response_data[:status_code] # Inferred 200 or nil
        # reason_phrase not applicable for local gpt4all
      }
    end

    def _gpt4all_handle_call_outcome(response_data:)
      if response_data[:error]
        # The original code had a specific error logging format.
        Boxcars.error(["Error from gpt4all engine: #{response_data[:error].message}",
                       response_data[:error].backtrace&.first(5)&.join("\n   ")].compact.join("\n   "), :red)
        raise response_data[:error]
      elsif !response_data[:success]
        # This case might be redundant if gpt4all gem always raises on error
        raise Error, "Unknown error from Gpt4all"
      else
        response_data.dig(:parsed_json, "text") # Extract the text from our structured hash
      end
    end
  end
end
