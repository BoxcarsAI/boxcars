# frozen_string_literal: true

module Boxcars
  # @abstract
  class LLM
    # A LLM is a container for a single tool to run.
    # @param name [String] The name of the LLM. Defaults to classname.
    # @param description [String] A description of the LLM.
    def initialize(description:, name: nil)
      @name = name || self.class.name
      @description = description
    end

    # Get an answer from the LLM.
    # @param question [String] The question to ask the LLM.
    def run(question)
      raise NotImplementedError
    end
  end
end

require "boxcars/llm/llm_result"
require "boxcars/llm/llm_open_ai"
