# frozen_string_literal: true

module Boxcars
  # @abstract
  class Engine
    attr_reader :prompts, :batch_size, :user_id

    # An Engine is used by Boxcars to generate output from prompts
    # @param name [String] The name of the Engine. Defaults to classname.
    # @param description [String] A description of the Engine.
    # @param prompts [Array<Prompt>] The prompts to use for the Engine.
    # @param batch_size [Integer] The number of prompts to send to the Engine at a time.
    # @param user_id [String, Integer] The ID of the user using this Engine (optional for observability).
    def initialize(description: 'Engine', name: nil, prompts: [], batch_size: 20, user_id: nil)
      @name = name || self.class.name
      @description = description
      @prompts = prompts
      @batch_size = batch_size
      @user_id = user_id
    end

    # Get an answer from the Engine.
    # @param question [String] The question to ask the Engine.
    def run(question)
      raise NotImplementedError
    end

    # Provider/runtime capabilities used by newer execution strategies
    # (e.g. tool-calling planners and structured-output helpers).
    # Engines can override this to advertise support.
    def capabilities
      {
        tool_calling: false,
        structured_output_json_schema: false,
        native_json_object: false,
        responses_api: false
      }
    end

    def supports?(capability)
      capabilities.fetch(capability.to_sym, false)
    end

    # calculate the number of tokens used
    def get_num_tokens(text:)
      text.split.length # TODO: hook up to token counting gem
    end

    # Get generation informaton
    # @param sub_choices [Array<Hash>] The choices to get generation info for.
    # @return [Array<Generation>] The generation information.
    def generation_info(sub_choices)
      sub_choices.map do |choice|
        Generation.new(
          text: (choice.dig("message", "content") || choice["text"]).to_s,
          generation_info: {
            finish_reason: choice.fetch("finish_reason", nil),
            logprobs: choice.fetch("logprobs", nil)
          }
        )
      end
    end

    # Generate one completion result from a single prompt/input pair.
    # @param prompt [Prompt] The prompt object to run.
    # @param inputs [Hash] Input values for prompt interpolation.
    # @param stop [Array<String>, nil] Optional stop words.
    # @return [EngineResult] A single-result engine output wrapper.
    def generate_one(prompt:, inputs: {}, stop: nil)
      generate(prompts: [[prompt, inputs]], stop:)
    end

    # Call out to the LLM endpoint with one or more prompt/input pairs.
    # @param prompts [Array<Array(Prompt, Hash)>] Prompt/input pairs to run.
    # @param stop [Array<String>, nil] Optional stop words.
    # @return [EngineResult] The full engine output.
    def generate(prompts:, stop: nil)
      choices = []
      token_usage = {}
      token_usage_details = {}
      raw_usage = []
      # Get the token usage from the response.
      # Includes prompt, completion, and total tokens used.
      inkeys = %w[completion_tokens prompt_tokens total_tokens].freeze
      prompts.each_slice(batch_size) do |sub_prompts|
        sub_prompts.each do |sprompt, inputs|
          process_generate_prompt!(
            prompt: sprompt,
            inputs:,
            stop:,
            choices:,
            token_usage:,
            token_usage_details:,
            raw_usage:,
            inkeys:
          )
        end
      end

      generations = []
      prompts.each_with_index do |_prompt, i|
        sub_choices = choices[i, 1] || []
        generations.push(generation_info(sub_choices))
      end
      EngineResult.new(generations:, engine_output: { token_usage:, token_usage_details:, raw_usage: })
    end

    def process_generate_prompt!(prompt:, inputs:, stop:, choices:, token_usage:, token_usage_details:, raw_usage:, inkeys:)
      params = {}
      params[:stop] = stop if stop
      process_generate_response!(
        api_response_hash: client(prompt:, inputs:, **params),
        choices:,
        token_usage:,
        token_usage_details:,
        raw_usage:,
        inkeys:
      )
    end

    def process_generate_response!(api_response_hash:, choices:, token_usage:, token_usage_details:, raw_usage:, inkeys:)
      normalized_response = normalize_generate_response(api_response_hash)
      unless normalized_response.is_a?(Hash)
        raise TypeError, "Expected Hash from client method, got #{api_response_hash.class}: #{api_response_hash.inspect}"
      end

      validate_response!(normalized_response)
      append_generate_choices!(choices:, api_response_hash: normalized_response)
      aggregate_generate_usage!(api_response_hash: normalized_response, token_usage:, token_usage_details:, raw_usage:, inkeys:)
    end

    def normalize_generate_response(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested), out|
          normalized_key = key.is_a?(Symbol) ? key.to_s : key
          out[normalized_key] = normalize_generate_response(nested)
        end
      when Array
        value.map { |nested| normalize_generate_response(nested) }
      else
        value
      end
    end

    def append_generate_choices!(choices:, api_response_hash:)
      current_choices = api_response_hash["choices"]
      if current_choices.is_a?(Array)
        choices.concat(current_choices)
      elsif api_response_hash["output"]
        # Synthesize a choice from non-Chat providers (e.g., OpenAI Responses API for GPT-5)
        synthesized_text = extract_answer(api_response_hash)
        choices << { "message" => { "content" => synthesized_text }, "finish_reason" => "stop" }
      elsif api_response_hash["completion"]
        choices << {
          "text" => api_response_hash["completion"],
          "finish_reason" => api_response_hash["stop_reason"]
        }
      elsif api_response_hash["text"]
        choices << { "text" => api_response_hash["text"], "finish_reason" => api_response_hash["finish_reason"] }
      else
        Boxcars.logger&.warn "No generation content found in API response: #{api_response_hash.inspect}"
      end
    end

    def aggregate_generate_usage!(api_response_hash:, token_usage:, token_usage_details:, raw_usage:, inkeys:)
      api_usage = api_response_hash["usage"]
      unless api_usage.is_a?(Hash)
        Boxcars.logger&.warn "No 'usage' data found in API response: #{api_response_hash.inspect}"
        return
      end

      raw_usage << api_usage.dup
      usage_keys = inkeys & api_usage.keys
      usage_keys.each { |key| token_usage[key] = token_usage[key].to_i + api_usage[key] }
      aggregate_token_usage_details!(token_usage_details:, api_usage:)
    end

    def aggregate_token_usage_details!(token_usage_details:, api_usage:)
      input_tokens = usage_token_value(api_usage, "input_tokens") || usage_token_value(api_usage, "prompt_tokens")
      output_tokens = usage_token_value(api_usage, "output_tokens") || usage_token_value(api_usage, "completion_tokens")
      total_tokens = usage_token_value(api_usage, "total_tokens")
      total_tokens ||= input_tokens + output_tokens if input_tokens && output_tokens

      add_usage_detail!(token_usage_details, :input_tokens, input_tokens)
      add_usage_detail!(token_usage_details, :output_tokens, output_tokens)
      add_usage_detail!(token_usage_details, :total_tokens, total_tokens)

      cached_input_tokens = usage_nested_token_value(api_usage, "input_tokens_details", "cached_tokens")
      cached_input_tokens ||= usage_nested_token_value(api_usage, "prompt_tokens_details", "cached_tokens")
      add_usage_detail!(token_usage_details, :cached_input_tokens, cached_input_tokens)

      return unless input_tokens && !cached_input_tokens.nil?

      add_usage_detail!(token_usage_details, :uncached_input_tokens, [input_tokens - cached_input_tokens, 0].max)
    end

    def add_usage_detail!(token_usage_details, key, value)
      return if value.nil?

      token_usage_details[key] = token_usage_details.fetch(key, 0) + value.to_i
    end

    def usage_token_value(usage_hash, key)
      usage_hash[key] || usage_hash[key.to_sym]
    end

    def usage_nested_token_value(usage_hash, parent_key, key)
      parent = usage_hash[parent_key] || usage_hash[parent_key.to_sym]
      return nil unless parent.is_a?(Hash)

      parent[key] || parent[key.to_sym]
    end

    def extract_answer(response)
      # Handle different response formats
      if response["choices"]
        response["choices"].map { |c| c.dig("message", "content") || c["text"] }.join("\n").strip
      elsif response["candidates"]
        response["candidates"].map { |c| c.dig("content", "parts", 0, "text") }.join("\n").strip
      elsif response["completion"]
        response["completion"].to_s
      else
        response["output"] || response.to_s
      end
    end

    # Validate API response and raise appropriate errors
    # @param response [Hash] The response to validate.
    # @param must_haves [Array<String>] The keys that must be in the response.
    # @raise [KeyError] if there is an issue with the API key.
    # @raise [Boxcars::Error] if the response is not valid.
    def validate_response!(response, must_haves: %w[choices])
      # Check for API errors first
      if response['error']
        error_details = response['error']
        raise Boxcars::Error, "API error: #{error_details}" unless error_details.is_a?(Hash)

        # Some SDK response objects serialize `error: null` as a hash with nil values.
        # Treat that as no error and continue validating required response content.
        has_error_content = error_details.any? do |_k, v|
          if v.is_a?(Hash)
            v.values.any? { |nested| !(nested.nil? || (nested.respond_to?(:empty?) && nested.empty?)) }
          elsif v.is_a?(Array)
            !v.empty?
          else
            !(v.nil? || (v.respond_to?(:empty?) && v.empty?))
          end
        end
        return if !has_error_content && must_haves.any? { |key| response.key?(key) && !response[key].nil? }
        if !has_error_content
          # No actual error payload; continue to required key checks below.
        else
          code = error_details['code'] || error_details[:code]
          message = error_details['message'] || error_details[:message] || 'unknown error'

          # Handle common API key errors
          raise KeyError, "API key not valid or permission denied" if ['invalid_api_key', 'permission_denied'].include?(code)

          raise Boxcars::Error, "API error: #{message}"
        end

      end

      # Check for required keys in response
      has_required_content = must_haves.any? { |key| response.key?(key) && !response[key].nil? }
      return if has_required_content

      raise Boxcars::Error, "Response missing required keys. Expected one of: #{must_haves.join(', ')}"
    end
  end
end

require 'boxcars/engine/unified_observability'
require "boxcars/engine/openai_compatible_chat_helpers"
require "boxcars/engine/engine_result"
require "boxcars/engine/intelligence_base"
require "boxcars/engine/anthropic"
require "boxcars/engine/cohere"
require "boxcars/engine/groq"
require "boxcars/engine/ollama"
require "boxcars/engine/openai"
require "boxcars/engine/perplexityai"
require "boxcars/engine/gpt4all_eng"
require "boxcars/engine/gemini_ai"
require "boxcars/engine/cerebras"
require "boxcars/engine/google"
require "boxcars/engine/together"
