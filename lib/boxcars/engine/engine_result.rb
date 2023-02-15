# frozen_string_literal: true

module Boxcars
  # Class that contains all the relevant information for a engine result
  class EngineResult
    attr_accessor :generations, :engine_output

    def initialize(generations: nil, engine_output: nil)
      @generations = generations
      @engine_output = engine_output
    end
  end
end
