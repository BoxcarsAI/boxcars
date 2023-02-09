# frozen_string_literal: true

module Boxcars
  # @abstract
  class Conductor
    attr_reader :llm, :boxcars

    # A Conductor will use a LLM to run a series of boxcars.
    # @param llm [Boxcars::LLM] The LLM to use for this conductor.
    # @param boxcars [Array<Boxcars::Boxcar>] The boxcars to run.
    def initialize(llm:, boxcars:)
      @llm = llm
      @boxcars = boxcars
    end

    # Get an answer from the conductor.
    # @param question [String] The question to ask the conductor.
    # @return [String] The answer to the question.
    def run(question)
      raise NotImplementedError
    end
  end
end
