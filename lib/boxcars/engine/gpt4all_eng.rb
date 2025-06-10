# frozen_string_literal: true

require 'gpt4all'
require 'json' # For pretty_generate

module Boxcars
  # A engine that uses local GPT4All API.
  class Gpt4allEng < Engine
    include UnifiedObservability
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
      user_id = kwargs.delete(:user_id)
      @gpt4all_params = DEFAULT_PARAMS.merge(kwargs) # Store merged params
      @prompts = prompts
      @batch_size = batch_size # Retain if used by other methods
      super(description:, name:, user_id:)
    end

    def client(prompt:, inputs: {}, **kwargs)
      start_time = Time.now
      response_data = { response_obj: nil, parsed_json: nil, success: false, error: nil, status_code: nil }
      # current_params are the effective parameters for this call, including defaults and overrides
      current_params = @gpt4all_params.merge(kwargs)
      # api_request_params for GPT4All is just the input text.
      api_request_params, gpt4all_instance = nil
      current_prompt_object = prompt.is_a?(Array) ? prompt.first : prompt
      begin
        gpt4all_instance = Gpt4all::ConversationalAI.new
        # prepare_resources might download models, could take time.
        # Consider if this setup should be outside the timed/tracked client call for long-running setup.
        # For now, including it as it's part of the interaction.
        gpt4all_instance.prepare_resources(force_download: false)
        gpt4all_instance.start_bot

        # GPT4All gem's prompt method takes a string.
        prompt_text_for_api = current_prompt_object.as_prompt(inputs:)
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
          inputs:,
          conversation_for_api: api_request_params&.dig(:prompt),
          user_id:
        }

        track_ai_generation(
          duration_ms:,
          current_params:,
          request_context:,
          response_data:,
          provider: :gpt4all
        )
      end

      _gpt4all_handle_call_outcome(response_data:)
    end

    def run(question, **)
      prompt = Prompt.new(template: question)
      answer = client(prompt:, inputs: {}, **)
      Boxcars.debug("Answer: #{answer}", :cyan)
      answer
    end

    # Added for consistency
    def default_params
      @gpt4all_params
    end

    private

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
