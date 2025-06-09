# frozen_string_literal: true

module Boxcars
  # @abstract
  class Engine
    attr_reader :prompts, :batch_size

    # An Engine is used by Boxcars to generate output from prompts
    # @param name [String] The name of the Engine. Defaults to classname.
    # @param description [String] A description of the Engine.
    # @param prompts [Array<Prompt>] The prompts to use for the Engine.
    # @param batch_size [Integer] The number of prompts to send to the Engine at a time.
    def initialize(description: 'Engine', name: nil, prompts: [], batch_size: 20)
      @name = name || self.class.name
      @description = description
      @prompts = prompts
      @batch_size = batch_size
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

          # Handle different response formats:
          # - New format: response_data hash with :parsed_json key (Groq, Gemini)
          # - Legacy format: direct API response hash (OpenAI, others)
          api_response_hash = if client_response.is_a?(Hash) && client_response.key?(:parsed_json)
                                client_response[:parsed_json]
                              else
                                client_response
                              end

          # Ensure we have a hash to work with
          unless api_response_hash.is_a?(Hash)
            raise TypeError, "Expected Hash from client method, got #{api_response_hash.class}: #{api_response_hash.inspect}"
          end

          check_response(api_response_hash)

          current_choices = api_response_hash["choices"]
          if current_choices.is_a?(Array)
            choices.concat(current_choices)
          else
            Boxcars.logger&.warn "No 'choices' found in API response: #{api_response_hash.inspect}"
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
