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

    def default_params
      { question: {
          type: :string,
          description: "a Ruby programming string that will compute the answer to a math question",
          required: true
          } }
    end

    # run a ruby calculator question
    # @param question [String] The question to ask Google.
    # @return [String] The answer to the question.
    def run(question)
      call(inputs: { question: })[:answer]
    end

    def call(inputs:)
      question = inputs[:question] || inputs["question"]
      code = "puts(#{question})"
      ruby_executor = Boxcars::RubyREPL.new
      { answer: ruby_executor.call(code:) }
    end

    def apply(input_list:)
      input_list.map { |inputs| call(inputs:) }
    end
  end
end
