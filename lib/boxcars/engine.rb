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
  end
end

require "boxcars/engine/engine_result"
require "boxcars/engine/anthropic"
require "boxcars/engine/cohere"
require "boxcars/engine/groq"
require "boxcars/engine/openai"
require "boxcars/engine/perplexityai"
require "boxcars/engine/gpt4all_eng"
