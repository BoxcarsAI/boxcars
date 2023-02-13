# frozen_string_literal: true

module Boxcars
  # @abstract
  class Boxcar
    attr_reader :name, :description

    # A Boxcar is a container for a single tool to run.
    # @param name [String] The name of the boxcar. Defaults to classname.
    # @param description [String] A description of the boxcar.
    def initialize(description:, name: nil)
      @name = name || self.class.name
      @description = description
    end

    # Get an answer from the boxcar.
    # @param question [String] The question to ask the boxcar.
    # @return [String] The answer to the question.
    def run(question)
      raise NotImplementedError
    end
  end
end

require "boxcars/boxcar/boxcar_with_llm"
require "boxcars/boxcar/calculator"
require "boxcars/boxcar/serp"
require "boxcars/boxcar/sql"
