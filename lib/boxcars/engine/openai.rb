# frozen_string_literal: true

require "openai"
require "json"
require "securerandom"

module Boxcars
  # Engine that talks to OpenAI’s REST API.
  class Openai < Engine # rubocop:disable Metrics/ClassLength
    # include Boxcars::EngineHelpers
    include UnifiedObservability

    CHAT_MODEL_REGEX = /(^gpt-4)|(-turbo\b)|(^o\d)|(gpt-3\.5-turbo)/
    O_SERIES_REGEX   = /^o/
    GPT5_MODEL_REGEX = /\Agpt-[56].*/

    DEFAULT_PARAMS = {
      model: "gpt-4o-mini",
      temperature: 0.1,
      max_tokens: 4096
    }.freeze

    DEFAULT_NAME        = "OpenAI engine"
    DEFAULT_DESCRIPTION = "Useful when you need AI to answer questions. Ask targeted questions."

    attr_reader :prompts, :open_ai_params, :batch_size

    # --------------------------------------------------------------------------
    #  Construction
    # --------------------------------------------------------------------------
    def initialize(name: DEFAULT_NAME,
                   description: DEFAULT_DESCRIPTION,
                   prompts: [],
                   batch_size: 20,
                   **kwargs)
      user_id          = kwargs.delete(:user_id)
      @open_ai_params  = adjust_for_o_series!(DEFAULT_PARAMS.merge(kwargs))
      @prompts         = prompts
      @batch_size      = batch_size
      super(description:, name:, user_id:)
    end

    # --------------------------------------------------------------------------
    #  Public API
    # --------------------------------------------------------------------------
    def client(prompt:, inputs: {}, openai_access_token: nil, **kwargs)
      start_time       = Time.now
      response_data    = { response_obj: nil, parsed_json: nil,
                           success: false, error: nil, status_code: nil }
      current_params   = open_ai_params.merge(kwargs)
      is_chat_model    = chat_model?(current_params[:model])
      prompt_object    = prompt.is_a?(Array) ? prompt.first : prompt
      api_request      = build_api_request(prompt_object, inputs, current_params, chat: is_chat_model)

      begin
        raw_response = execute_api_call(
          self.class.open_ai_client(openai_access_token:),
          is_chat_model,
          api_request
        )
        process_response(raw_response, response_data)
      rescue ::OpenAI::Error, StandardError => e
        handle_error(e, response_data)
      ensure
        track_openai_observability(
          {
            start_time:,
            prompt_object: prompt_object,
            inputs: inputs,
            api_request: api_request,
            current_params: current_params,
            is_chat_model: is_chat_model
          },
          response_data
        )
      end

      handle_call_outcome(response_data:)
    end

    # Convenience one-shot helper used by Engine#generate
    def run(question, **)
      prompt      = Prompt.new(template: question)
      raw_json    = client(prompt:, inputs: {}, **)
      ans         = extract_answer(raw_json)
      Boxcars.debug("Answer: #{ans}", :cyan)
      ans
    end

    # Expose the defaults so callers can introspect or dup/merge them
    def default_params = open_ai_params

    # --------------------------------------------------------------------------
    #  Class helpers
    # --------------------------------------------------------------------------
    def self.open_ai_client(openai_access_token: nil)
      ::OpenAI::Client.new(
        access_token: Boxcars.configuration.openai_access_token(openai_access_token:),
        organization_id: Boxcars.configuration.organization_id,
        log_errors: true
      )
    end

    # -- Public helper -------------------------------------------------------------
    # Some callers outside this class still invoke `validate_response!` directly.
    # It simply raises if the JSON body contains an "error" payload.
    def validate_response!(response, must_haves: %w[choices])
      if response.is_a?(Hash) && response.key?("output")
        super(response, must_haves: %w[output])
      else
        super
      end
    end

    private

    # -- Request construction ---------------------------------------------------
    def build_api_request(prompt_object, inputs, params, chat:)
      use_responses = params.delete(:use_responses_api) || gpt5_model?(params[:model])
      if use_responses
        build_responses_params(prompt_object, inputs, params.dup)
      elsif chat
        build_chat_params(prompt_object, inputs, params.dup)
      else
        build_completion_params(prompt_object, inputs, params.dup)
      end
    end

    def build_chat_params(prompt_object, inputs, params)
      po        = if prompt_object.is_a?(Boxcars::Prompt)
                    prompt_object
                  else
                    Boxcars::Prompt.new(template: prompt_object.to_s)
                  end
      formatted = po.as_messages(inputs).merge(params)
      adjust_for_o_series!(formatted)
    end

    def build_completion_params(prompt_object, inputs, params)
      prompt_txt = prompt_object.as_prompt(inputs:)
      prompt_txt = prompt_txt[:prompt] if prompt_txt.is_a?(Hash) && prompt_txt.key?(:prompt)
      { prompt: prompt_txt }.merge(params).tap { |h| h.delete(:messages) }
    end

    def build_responses_params(prompt_object, inputs, params)
      po = if prompt_object.is_a?(Boxcars::Prompt)
             prompt_object
           else
             Boxcars::Prompt.new(template: prompt_object.to_s)
           end

      msg_hash  = po.as_messages(inputs)
      messages  = msg_hash[:messages].is_a?(Array) ? msg_hash[:messages] : []
      input_str = messages_to_input(messages)

      p = params.dup
      p.delete(:messages)
      p.delete(:response_format)
      p.delete(:stop)
      p.delete(:temperature)
      p[:max_output_tokens] = p.delete(:max_tokens) if p.key?(:max_tokens) && !p.key?(:max_output_tokens)
      if (effort = p.delete(:reasoning_effort))
        p[:reasoning] = { effort: effort }
      end

      formatted = { model: p[:model], input: input_str, _use_responses_api: true }
      p.each { |k, v| formatted[k] = v unless k == :model }
      formatted
    end

    def messages_to_input(messages)
      return "" unless messages.is_a?(Array)

      messages.map { |m| "#{m[:role]}: #{m[:content]}" }.join("\n")
    end

    # -- API call / response ----------------------------------------------------
    def execute_api_call(client, chat_mode, api_request)
      if api_request[:_use_responses_api]
        call_params = api_request.dup
        call_params.delete(:_use_responses_api)
        Boxcars.debug("Input after formatting:\n#{call_params[:input]}", :cyan) if Boxcars.configuration.log_prompts
        unless client.respond_to?(:responses)
          raise StandardError,
                "OpenAI Responses API not supported by installed ruby-openai gem. Upgrade ruby-openai to >7.0 version."
        end

        client.responses.create(parameters: call_params)
      elsif chat_mode
        log_messages_debug(api_request[:messages]) if Boxcars.configuration.log_prompts
        client.chat(parameters: api_request)
      else
        Boxcars.debug("Prompt after formatting:\n#{api_request[:prompt]}", :cyan) if Boxcars.configuration.log_prompts
        client.completions(parameters: api_request)
      end
    end

    def process_response(raw, data)
      data[:response_obj] = raw
      data[:parsed_json]  = raw

      if (msg = openai_error_message(raw))
        data[:success]     = false
        data[:status_code] = raw&.dig("error", "code") || 500
        data[:error]       = StandardError.new(msg)
      else
        data[:success]     = true
        data[:status_code] = 200
      end
    end

    def handle_error(error, data)
      data[:error]        = error
      data[:success]      = false
      data[:status_code]  = error.respond_to?(:http_status) ? error.http_status : 500
    end

    def handle_call_outcome(response_data:)
      return response_data[:parsed_json] if response_data[:success]

      if response_data[:error]
        raise_api_error(response_data[:error])
      else
        raise_body_error(response_data[:response_obj])
      end
    end

    # -- Extraction helpers -----------------------------------------------------
    def extract_answer_from_choices(choices)
      raise Error, "OpenAI: No choices found in response" unless choices.is_a?(Array) && choices.any?

      content = choices.map { |c| c.dig("message", "content") }.compact
      return content.join("\n").strip unless content.empty?

      text = choices.map { |c| c["text"] }.compact
      return text.join("\n").strip unless text.empty?

      raise Error, "OpenAI: Could not extract answer from choices"
    end

    def extract_answer_from_output(output_items) # rubocop:disable Metrics/PerceivedComplexity,Metrics/MethodLength
      return nil unless output_items.is_a?(Array) && output_items.any?

      texts = []

      output_items.each do |i| # rubocop:disable Metrics/BlockLength
        next unless i.is_a?(Hash)

        case i["type"]
        when "output_text"
          content = i["content"]
          if content.is_a?(Array)
            # rubocop:disable Metrics/BlockNesting
            texts << content.filter_map { |c|
              if c.is_a?(Hash)
                if c["text"].is_a?(String)
                  c["text"]
                else
                  (c["text"].is_a?(Hash) ? (c["text"]["value"] || c["text"]["text"]) : nil)
                end
              end
            }.join
            # rubocop:enable Metrics/BlockNesting
          elsif content.is_a?(String)
            texts << content
          end
          # Some Responses payloads may include a direct "text" field.
          if i["text"].is_a?(String)
            texts << i["text"]
          elsif i["text"].is_a?(Hash)
            texts << (i["text"]["value"] || i["text"]["text"])
          end
        when "message"
          content = i["content"]
          if content.is_a?(Array)
            parts = content.filter_map do |c|
              next unless c.is_a?(Hash) && ["output_text", "text"].include?(c["type"])

              t = c["text"]
              if t.is_a?(String)
                t
              elsif t.is_a?(Hash)
                t["value"] || t["text"]
              elsif c["content"].is_a?(String)
                c["content"]
              end
            end
            texts << parts.join
          end
        end
      end

      return nil if texts.empty?

      texts.join("\n").strip
    end

    def extract_answer(json)
      if json.is_a?(Hash)
        if json["output_text"].is_a?(String) && !json["output_text"].strip.empty?
          return json["output_text"].strip
        elsif json["output_text"].is_a?(Array)
          joined = json["output_text"].map do |t|
            if t.is_a?(String)
              t
            elsif t.is_a?(Hash)
              t["value"] || t["text"] || t["content"]
            end
          end.compact.join("\n").strip
          return joined unless joined.empty?
        end

        if json["output"].is_a?(Array)
          out = extract_answer_from_output(json["output"])
          return out unless out.nil? || out.strip.empty?
        end
      end

      choices = json["choices"]
      return extract_answer_from_choices(choices) if choices

      # Fallback: attempt to find any text in nested Responses payloads
      fallback = deep_extract_texts(json)
      return fallback unless fallback.nil? || fallback.strip.empty?

      raise Error, "OpenAI: Could not extract answer"
    end

    def deep_extract_texts(obj)
      texts = []
      stack = [obj]
      while (cur = stack.pop)
        case cur
        when Hash
          texts << cur["output_text"] if cur["output_text"].is_a?(String)
          texts << cur["text"] if cur["text"].is_a?(String)
          texts << cur["content"] if cur["content"].is_a?(String)
          cur.each_value do |v|
            stack << v if v.is_a?(Hash) || v.is_a?(Array)
          end
        when Array
          cur.each { |v| stack << v if v.is_a?(Hash) || v.is_a?(Array) }
        end
      end
      aggregated = texts.map { |t| t.to_s.strip }.reject(&:empty?).join("\n")
      aggregated.empty? ? nil : aggregated
    end

    # -- Utility helpers --------------------------------------------------------
    def chat_model?(model_name) = CHAT_MODEL_REGEX.match?(model_name)
    def gpt5_model?(model_name) = GPT5_MODEL_REGEX.match?(model_name.to_s)

    def openai_error_message(json)
      err = json&.dig("error")
      return unless err

      err.is_a?(Hash) ? "#{err['type']}: #{err['message']}" : err.to_s
    end

    def adjust_for_o_series!(params)
      return params unless params[:model] =~ O_SERIES_REGEX

      params[:messages][0][:role] = :user if params.dig(:messages, 0, :role).to_s == "system"
      params.delete(:response_format)
      params.delete(:stop)
      if params.key?(:max_tokens) && !params.key?(:max_completion_tokens)
        params[:max_completion_tokens] =
          params.delete(:max_tokens)
      end
      params.delete(:temperature)
      params
    end

    def log_messages_debug(messages)
      return unless messages.is_a?(Array)

      Boxcars.debug(
        messages.last(2).map { |m| ">>>>>> Role: #{m[:role]} <<<<<<\n#{m[:content]}" }.join("\n"),
        :cyan
      )
    end

    # -- Error raising ----------------------------------------------------------
    def raise_api_error(err)
      msg = err.message
      msg += " - Details: #{err.json_body}" if err.respond_to?(:json_body) && err.json_body
      Boxcars.error("OpenAI Error: #{msg} (#{err.class})", :red)
      raise err
    end

    def raise_body_error(response_obj)
      raise Error, openai_error_message(response_obj) || "Unknown error from OpenAI API"
    end

    # -- Observability ----------------------------------------------------------
    def track_openai_observability(call_ctx, response_data)
      duration_ms = ((Time.now - call_ctx[:start_time]) * 1000).round
      api_req     = call_ctx[:api_request] || {}

      track_ai_generation(
        duration_ms: duration_ms,
        current_params: call_ctx[:current_params],
        request_context: {
          prompt: call_ctx[:prompt_object],
          inputs: call_ctx[:inputs],
          user_id: user_id,
          conversation_for_api: if api_req.key?(:input)
                                  api_req[:input]
                                elsif call_ctx[:is_chat_model]
                                  api_req[:messages]
                                else
                                  api_req[:prompt]
                                end
        },
        response_data: response_data,
        provider: :openai
      )
    end
  end
end
