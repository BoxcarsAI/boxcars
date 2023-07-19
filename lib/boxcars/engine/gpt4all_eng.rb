# frozen_string_literal: true

require 'gpt4all'
# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A engine that uses local GPT4All API.
  class Gpt4allEng < Engine
    attr_reader :prompts, :model_kwargs, :batch_size

    # the default name of the engine
    DEFAULT_NAME = "Gpt4all engine"
    # the default description of the engine
    DEFAULT_DESCRIPTION = "useful for when you need to use local AI to answer questions. " \
                          "You should ask targeted questions"

    # A engine is a container for a single tool to run.
    # @param name [String] The name of the engine. Defaults to "OpenAI engine".
    # @param description [String] A description of the engine. Defaults to:
    #        useful for when you need to use AI to answer questions. You should ask targeted questions".
    # @param prompts [Array<String>] The prompts to use when asking the engine. Defaults to [].
    # @param batch_size [Integer] The number of prompts to send to the engine at once. Defaults to 2.
    def initialize(name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, prompts: [], batch_size: 2, **_kwargs)
      @prompts = prompts
      @batch_size = batch_size
      super(description: description, name: name)
    end

    # Get an answer from the engine.
    # @param prompt [String] The prompt to use when asking the engine.
    # @param openai_access_token [String] The access token to use when asking the engine.
    #   Defaults to Boxcars.configuration.openai_access_token.
    # @param kwargs [Hash] Additional parameters to pass to the engine if wanted.
    def client(prompt:, inputs: {}, **_kwargs)
      gpt4all = Gpt4all::ConversationalAI.new
      gpt4all.prepare_resources(force_download: false)
      gpt4all.start_bot
      input_text = prompt.as_prompt(inputs: inputs)[:prompt]
      Boxcars.debug("Prompt after formatting:\n#{input_text}", :cyan) if Boxcars.configuration.log_prompts
      gpt4all.prompt(input_text)
    rescue StandardError => e
      Boxcars.error(["Error from gpt4all engine: #{e}", e.backtrace[-5..-1]].flatten.join("\n   "))
    ensure
      gpt4all.stop_bot
    end

    # get an answer from the engine for a question.
    # @param question [String] The question to ask the engine.
    # @param kwargs [Hash] Additional parameters to pass to the engine if wanted.
    def run(question, **kwargs)
      prompt = Prompt.new(template: question)
      answer = client(prompt: prompt, **kwargs)
      Boxcars.debug("Answer: #{answer}", :cyan)
      answer
    end
  end
end
