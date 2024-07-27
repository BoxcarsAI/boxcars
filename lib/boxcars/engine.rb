# frozen_string_literal: true

module Boxcars
  # @abstract
  class Engine
    # An Engine is used by Boxcars to generate output from prompts
    # @param name [String] The name of the Engine. Defaults to classname.
    # @param description [String] A description of the Engine.
    def initialize(description: 'Engine', name: nil)
      @name = name || self.class.name
      @description = description
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

    # Call out to OpenAI's endpoint with k unique prompts.
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
        sub_prompts.each do |sprompts, inputs|
          response = client(prompt: sprompts, inputs: inputs, **params)
          check_response(response)
          choices.concat(response["choices"])
          usage_keys = inkeys & response["usage"].keys
          usage_keys.each { |key| token_usage[key] = token_usage[key].to_i + response["usage"][key] }
        end
      end

      n = params.fetch(:n, 1)
      generations = []
      prompts.each_with_index do |_prompt, i|
        sub_choices = choices[i * n, (i + 1) * n]
        generations.push(generation_info(sub_choices))
      end
      EngineResult.new(generations: generations, engine_output: { token_usage: token_usage })
    end
    # rubocop:enable Metrics/AbcSize
  end
end

require "boxcars/engine/engine_result"
require "boxcars/engine/anthropic"
require "boxcars/engine/cohere"
require "boxcars/engine/groq"
require "boxcars/engine/ollama"
require "boxcars/engine/openai"
require "boxcars/engine/perplexityai"
require "boxcars/engine/gpt4all_eng"
