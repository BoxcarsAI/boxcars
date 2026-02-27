# frozen_string_literal: true

require 'json'

begin
  require "gpt4all"
rescue LoadError
  # Optional dependency: this engine remains available when the gem is installed.
end

module Boxcars
  # An engine that uses local GPT4All API.
  class Gpt4allEng < Engine
    include UnifiedObservability

    attr_reader :prompts, :model_kwargs, :batch_size, :gpt4all_params

    DEFAULT_NAME = "Gpt4all engine"
    DEFAULT_DESCRIPTION = "useful for when you need to use local AI to answer questions. " \
                          "You should ask targeted questions"
    DEFAULT_PARAMS = {
      model_name: "gpt4all-j-v1.3-groovy"
    }.freeze

    def initialize(name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, prompts: [], batch_size: 2, **kwargs)
      user_id = kwargs.delete(:user_id)
      @gpt4all_params = DEFAULT_PARAMS.merge(kwargs)
      @prompts = prompts
      @batch_size = batch_size
      super(description:, name:, user_id:)
    end

    def client(prompt:, inputs: {}, **kwargs)
      ensure_gpt4all_available!
      start_time = Time.now
      response_data = { response_obj: nil, parsed_json: nil, success: false, error: nil, status_code: nil }
      current_params = @gpt4all_params.merge(kwargs)
      api_request_params, gpt4all_instance = nil
      current_prompt_object = normalize_prompt_object(prompt)
      begin
        gpt4all_instance = Gpt4all::ConversationalAI.new
        gpt4all_instance.prepare_resources(force_download: false)
        gpt4all_instance.start_bot

        prompt_text_for_api = current_prompt_object.as_prompt(inputs:)
        prompt_text_for_api = prompt_text_for_api[:prompt] if prompt_text_for_api.is_a?(Hash) && prompt_text_for_api.key?(:prompt)
        api_request_params = { prompt: prompt_text_for_api }

        Boxcars.debug("Prompt after formatting:\n#{prompt_text_for_api}", :cyan) if Boxcars.configuration.log_prompts

        raw_response_text = gpt4all_instance.prompt(prompt_text_for_api)
        prompt_tokens = get_num_tokens(text: prompt_text_for_api.to_s)
        completion_tokens = get_num_tokens(text: raw_response_text.to_s)

        response_data[:response_obj] = raw_response_text
        response_data[:parsed_json] = {
          "text" => raw_response_text,
          "choices" => [
            {
              "text" => raw_response_text,
              "finish_reason" => "stop"
            }
          ],
          "usage" => {
            "prompt_tokens" => prompt_tokens,
            "completion_tokens" => completion_tokens,
            "total_tokens" => prompt_tokens + completion_tokens
          }
        }
        response_data[:success] = true
        response_data[:status_code] = 200
      rescue StandardError => e
        response_data[:error] = e
        response_data[:success] = false
      ensure
        gpt4all_instance&.stop_bot

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

      gpt4all_handle_call_outcome(response_data:)
    end

    def run(question, **)
      prompt = Prompt.new(template: question)
      response = client(prompt:, inputs: {}, **)
      answer = extract_answer(response)
      Boxcars.debug("Answer: #{answer}", :cyan)
      answer
    end

    def default_params
      @gpt4all_params
    end

    private

    def ensure_gpt4all_available!
      return if gpt4all_available?

      raise Boxcars::ConfigurationError,
            "Gpt4allEng requires the `gpt4all` gem. Add `gem \"gpt4all\"` to your application to use this engine."
    end

    def gpt4all_available?
      defined?(::Gpt4all::ConversationalAI)
    end

    def gpt4all_handle_call_outcome(response_data:)
      if response_data[:error]
        Boxcars.error(["Error from gpt4all engine: #{response_data[:error].message}",
                       response_data[:error].backtrace&.first(5)&.join("\n   ")].compact.join("\n   "), :red)
        raise response_data[:error]
      elsif !response_data[:success]
        raise Error, "Unknown error from Gpt4all"
      else
        response_data[:parsed_json]
      end
    end
  end
end
