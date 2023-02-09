# frozen_string_literal: true

module Boxcars
  # Class that contains all the relevant information for a LLM result
  class LLMResult
    attr_accessor :generations, :llm_output

    def initialize(generations: nil, llm_output: nil)
      @generations = generations
      @llm_output = llm_output
    end
  end
end
