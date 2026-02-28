# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A Boxcar executes ruby code to do math
  class RubyCalculator < Boxcar
    # the description of this engine boxcar
    CALCDESC = "will run a ruby calculation to answer a math question"

    # @param kwargs [Hash] Any other keyword arguments to pass to the parent class.
    def initialize(**kwargs)
      kwargs[:name] ||= "RubyCalculator"
      kwargs[:description] ||= CALCDESC
      kwargs[:parameters] ||= default_params

      super
    end

    # Default JSON-like parameter description for tool wiring.
    # @return [Hash] Parameter descriptor hash keyed by `:question`.
    def default_params
      { question: {
          type: :string,
          description: "a Ruby programming string that will compute the answer to a math question",
          required: true
          } }
    end

    # run a ruby calculator question
    # @param question [String] Ruby expression to evaluate.
    # @return [Boxcars::Result] Execution result from the Ruby REPL helper.
    def run(question)
      run_result(question)
    end

    # Execute one Ruby calculator request using the normalized Boxcar input contract.
    # @param inputs [Hash] Expected to contain `:question` (or `"question"`).
    # @return [Hash] `{ answer: Boxcars::Result }`.
    def call(inputs:)
      question = input_value(inputs, :question)
      code = "puts(#{question})"
      ruby_executor = Boxcars::RubyREPL.new
      { answer: ruby_executor.call(code:) }
    end

  end
end
