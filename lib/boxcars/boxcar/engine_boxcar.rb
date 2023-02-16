# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # For Boxcars that use an engine to do their work.
  # @abstract
  class EngineBoxcar < Boxcars::Boxcar
    attr_accessor :prompt, :engine, :output_key

    # A Boxcar is a container for a single tool to run.
    # @param prompt [Boxcars::Prompt] The prompt to use for this boxcar with sane defaults.
    # @param name [String] The name of the boxcar. Defaults to classname.
    # @param description [String] A description of the boxcar.
    # @param engine [Boxcars::Engine] The engine to user for this boxcar. Can be inherited from a conductor if nil.
    def initialize(prompt:, engine:, output_key: "text", name: nil, description: nil)
      @prompt = prompt
      @engine = engine
      @output_key = output_key
      super(name: name, description: description)
    end

    def input_keys
      prompt.input_variables
    end

    def output_keys
      [output_key]
    end

    # # Check that all inputs are present.
    # def validate_inputs(inputs:)
    #   missing_keys = input_keys - inputs.keys
    #   raise Boxcars::ArgumentError, "Missing some input keys: #{missing_keys}" if missing_keys.any?

    #   inputs
    # end

    # def validate_outputs(outputs:)
    #   return if outputs.sort == output_keys.sort

    #   raise Boxcars::ArgumentError, "Did not get out keys that were expected, got: #{outputs}. Expected: #{output_keys}"
    # end

    def generate(input_list:)
      stop = input_list[0][:stop]
      prompts = []
      input_list.each do |inputs|
        new_prompt = prompt.format(**inputs)
        puts "Prompt after formatting:\n#{new_prompt.colorize(:cyan)}"
        prompts.push(new_prompt)
      end
      engine.generate(prompts: prompts, stop: stop)
    end

    def apply(input_list:)
      response = generate(input_list: input_list)
      response.generations.to_h do |generation|
        [output_key, generation[0].text]
      end
    end

    def predict(**kwargs)
      apply(input_list: [kwargs])[output_key]
    end

    def predict_and_parse(**kwargs)
      result = predict(**kwargs)
      if prompt.output_parser
        prompt.output_parser.parse(result)
      else
        result
      end
    end

    def apply_and_parse(input_list:)
      result = apply(input_list: input_list)
      if prompt.output_parser
        result.map { |r| prompt.output_parser.parse(r[output_key]) }
      else
        result
      end
    end

    def check_output_keys
      return unless output_keys.length != 1

      raise Boxcars::ArgumentError, "run not supported when there is not exactly one output key. Got #{output_keys}."
    end
  end
end
