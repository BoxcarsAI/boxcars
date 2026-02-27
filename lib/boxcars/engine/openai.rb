# frozen_string_literal: true

require "json"
require "securerandom"

module Boxcars
  # Engine that talks to OpenAI’s REST API.
  class Openai < Engine # rubocop:disable Metrics/ClassLength
    # include Boxcars::EngineHelpers
    include UnifiedObservability
    include OpenAICompatibleChatHelpers

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
      reject_deprecated_backend_kwargs!(kwargs)
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
      reject_deprecated_backend_kwargs!(kwargs)
      current_params   = open_ai_params.merge(kwargs)
      is_chat_model    = chat_model?(current_params[:model])
      prompt_object    = normalize_prompt_object(prompt)
      api_request      = build_api_request(prompt_object, inputs, current_params, chat: is_chat_model)

      begin
        raw_response = execute_api_call(
          self.class.provider_client(openai_access_token:),
          is_chat_model,
          api_request
        )
        process_response(raw_response, response_data)
      rescue StandardError => e
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

    # Expose the defaults so callers can introspect or dup/merge them
    def default_params = open_ai_params

    def capabilities
      model_name = open_ai_params[:model].to_s
      tool_capable = chat_model?(model_name) || gpt5_model?(model_name)

      {
        tool_calling: tool_capable,
        structured_output_json_schema: tool_capable,
        native_json_object: chat_model?(model_name),
        responses_api: gpt5_model?(model_name)
      }
    end

    # --------------------------------------------------------------------------
    #  Class helpers
    # --------------------------------------------------------------------------
    def self.provider_client(openai_access_token: nil)
      Boxcars::OpenAIClient.build(
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
      explicit_response_input = p.delete(:response_input)
      response_format = p.delete(:response_format)
      p.delete(:messages)
      p.delete(:stop)
      p.delete(:temperature)
      p[:max_output_tokens] = p.delete(:max_tokens) if p.key?(:max_tokens) && !p.key?(:max_output_tokens)
      if (effort = p.delete(:reasoning_effort))
        p[:reasoning] = { effort: effort }
      end
      if response_format
        p[:text] = merge_responses_text_format(text: p[:text], response_format: response_format)
      end

      formatted = { model: p[:model], input: explicit_response_input || input_str, _use_responses_api: true }
      p.each { |k, v| formatted[k] = v unless k == :model }
      formatted
    end

    def merge_responses_text_format(text:, response_format:)
      existing_text = text.is_a?(Hash) ? symbolize_keys_shallow(text) : {}
      normalized_format = normalize_responses_text_format(response_format)
      existing_text.merge(format: normalized_format)
    end

    def normalize_responses_text_format(response_format)
      return response_format unless response_format.is_a?(Hash)

      format = symbolize_keys_shallow(response_format)
      return format unless format[:type].to_s == "json_schema"

      schema_payload = if format[:json_schema].is_a?(Hash)
                         symbolize_keys_shallow(format[:json_schema])
                       else
                         format
                       end

      {
        type: "json_schema",
        name: schema_payload[:name],
        description: schema_payload[:description],
        strict: schema_payload[:strict],
        schema: schema_payload[:schema]
      }.compact
    end

    def symbolize_keys_shallow(hash)
      hash.each_with_object({}) do |(key, value), out|
        normalized_key = key.is_a?(String) || key.is_a?(Symbol) ? key.to_sym : key
        out[normalized_key] = value
      end
    end

    def messages_to_input(messages)
      return "" unless messages.is_a?(Array)

      messages.map { |m| "#{m[:role]}: #{m[:content]}" }.join("\n")
    end

    def reject_deprecated_backend_kwargs!(kwargs)
      deprecated_keys = %i[openai_client_backend client_backend]
      provided = deprecated_keys.select { |key| kwargs.key?(key) }
      return if provided.empty?

      keys = provided.map { |key| ":#{key}" }.join(", ")
      raise ConfigurationError,
            "#{keys} #{provided.length == 1 ? 'is' : 'are'} no longer supported. " \
            "Boxcars now uses the official OpenAI client path only."
    end

    # -- API call / response ----------------------------------------------------
    def execute_api_call(client, chat_mode, api_request)
      if api_request[:_use_responses_api]
        call_params = api_request.dup
        call_params.delete(:_use_responses_api)
        Boxcars.debug("Input after formatting:\n#{call_params[:input]}", :cyan) if Boxcars.configuration.log_prompts
        client.responses_create(parameters: call_params)
      elsif chat_mode
        log_messages_debug(api_request[:messages]) if Boxcars.configuration.log_prompts
        client.chat_create(parameters: api_request)
      else
        Boxcars.debug("Prompt after formatting:\n#{api_request[:prompt]}", :cyan) if Boxcars.configuration.log_prompts
        client.completions_create(parameters: api_request)
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
      data[:status_code]  = openai_compatible_error_status_code(error)
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

      output_items.each do |i|
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
      return if err.nil?

      if err.is_a?(Hash)
        type = err["type"] || err[:type]
        message = err["message"] || err[:message]
        code = err["code"] || err[:code]
        param = err["param"] || err[:param]

        # Some SDK objects serialize a null error as a hash with all-nil fields.
        return if [type, message, code, param].all?(&:nil?)

        return "#{type}: #{message}" if !type.nil? || !message.nil?

        return err.to_s
      end

      msg = err.to_s
      msg.empty? ? nil : msg
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
