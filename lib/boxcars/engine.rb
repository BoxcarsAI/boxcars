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
          text: choice.dig("message", "content") || choice["text"],
          generation_info: {
            finish_reason: choice.fetch("finish_reason", nil),
            logprobs: choice.fetch("logprobs", nil)
          }
        )
      end
    end

    # Call out to LLM's endpoint with k unique prompts.
    # @param prompts [Array<String>] The prompts to pass into the model.
    # @param inputs [Array<String>] The inputs to subsitite into the prompt.
    # @param stop [Array<String>] Optional list of stop words to use when generating.
    # @return [EngineResult] The full engine output.
    def generate(prompts:, stop: nil)
      params = {}
      params[:stop] = stop if stop
      choices = []
      token_usage = {}
      # Get the token usage from the response.
      # Includes prompt, completion, and total tokens used.
      inkeys = %w[completion_tokens prompt_tokens total_tokens].freeze
      prompts.each_slice(batch_size) do |sub_prompts|
        sub_prompts.each do |sprompt, inputs|
          client_response = client(prompt: sprompt, inputs:, **params)

          # All engines now return the parsed API response hash directly
          api_response_hash = client_response

          # Ensure we have a hash to work with
          unless api_response_hash.is_a?(Hash)
            raise TypeError, "Expected Hash from client method, got #{api_response_hash.class}: #{api_response_hash.inspect}"
          end

          validate_response!(api_response_hash)

          current_choices = api_response_hash["choices"]
          if current_choices.is_a?(Array)
            choices.concat(current_choices)
          elsif api_response_hash["output"]
            # Synthesize a choice from non-Chat providers (e.g., OpenAI Responses API for GPT-5)
            synthesized_text = extract_answer(api_response_hash)
            choices << { "message" => { "content" => synthesized_text }, "finish_reason" => "stop" }
          else
            Boxcars.logger&.warn "No 'choices' or 'output' found in API response: #{api_response_hash.inspect}"
          end

          api_usage = api_response_hash["usage"]
          if api_usage.is_a?(Hash)
            usage_keys = inkeys & api_usage.keys
            usage_keys.each { |key| token_usage[key] = token_usage[key].to_i + api_usage[key] }
          else
            Boxcars.logger&.warn "No 'usage' data found in API response: #{api_response_hash.inspect}"
          end
        end
      end

      n = params.fetch(:n, 1)
      generations = []
      prompts.each_with_index do |_prompt, i|
        sub_choices = choices[i * n, (i + 1) * n]
        generations.push(generation_info(sub_choices))
      end
      EngineResult.new(generations:, engine_output: { token_usage: })
    end

    def extract_answer(response)
      # Handle different response formats
      if response["choices"]
        response["choices"].map { |c| c.dig("message", "content") || c["text"] }.join("\n").strip
      elsif response["candidates"]
        response["candidates"].map { |c| c.dig("content", "parts", 0, "text") }.join("\n").strip
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

        code = error_details['code']
        message = error_details['message'] || 'unknown error'

        # Handle common API key errors
        raise KeyError, "API key not valid or permission denied" if ['invalid_api_key', 'permission_denied'].include?(code)

        raise Boxcars::Error, "API error: #{message}"

      end

      # Check for required keys in response
      has_required_content = must_haves.any? { |key| response.key?(key) && !response[key].nil? }
      return if has_required_content

      raise Boxcars::Error, "Response missing required keys. Expected one of: #{must_haves.join(', ')}"
    end
  end
end

require 'boxcars/engine/unified_observability'
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
