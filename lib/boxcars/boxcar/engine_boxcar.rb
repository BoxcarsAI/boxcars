# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # For Boxcars that use an engine to do their work.
  class EngineBoxcar < Boxcar
    attr_accessor :prompt, :engine, :output_key

    # A Boxcar is a container for a single tool to run.
    # @param prompt [Boxcars::Prompt] The prompt to use for this boxcar with sane defaults.
    # @param name [String] The name of the boxcar. Defaults to classname.
    # @param description [String] A description of the boxcar.
    # @param engine [Boxcars::Engine] The engine to user for this boxcar. Can be inherited from a conductor if nil.
    def initialize(prompt:, engine: nil, output_key: "text", name: nil, description: nil)
      @prompt = prompt
      @engine = engine || Boxcars.default_engine.new
      @output_key = output_key
      super(name: name, description: description)
    end

    # input keys for the prompt
    def input_keys
      prompt.input_variables
    end

    # output keys
    def output_keys
      [output_key]
    end

    # generate a response from the engine
    # @param input_list [Array<Hash>] A list of hashes of input values to use for the prompt.
    # @return [Boxcars::EngineResult] The result from the engine.
    def generate(input_list:)
      stop = input_list[0][:stop]
      prompts = []
      input_list.each do |inputs|
        new_prompt = prompt.format(**inputs)
        puts "Prompt after formatting:\n#{new_prompt.colorize(:cyan)}" if Boxcars.configuration.log_prompts
        prompts.push(new_prompt)
      end
      engine.generate(prompts: prompts, stop: stop)
    end

    # apply a response from the engine
    # @param input_list [Array<Hash>] A list of hashes of input values to use for the prompt.
    # @return [Hash] A hash of the output key and the output value.
    def apply(input_list:)
      response = generate(input_list: input_list)
      response.generations.to_h do |generation|
        [output_key, generation[0].text]
      end
    end

    # predict a response from the engine
    # @param kwargs [Hash] A hash of input values to use for the prompt.
    # @return [String] The output value.
    def predict(**kwargs)
      apply(input_list: [kwargs])[output_key]
    end

    # predict a response from the engine and parse it
    # @param kwargs [Hash] A hash of input values to use for the prompt.
    # @return [String] The output value.
    def predict_and_parse(**kwargs)
      result = predict(**kwargs)
      if prompt.output_parser
        prompt.output_parser.parse(result)
      else
        result
      end
    end

    # apply a response from the engine and parse it
    # @param input_list [Array<Hash>] A list of hashes of input values to use for the prompt.
    # @return [Array<String>] The output values.
    def apply_and_parse(input_list:)
      result = apply(input_list: input_list)
      if prompt.output_parser
        result.map { |r| prompt.output_parser.parse(r[output_key]) }
      else
        result
      end
    end

    # check that there is exactly one output key
    # @raise [Boxcars::ArgumentError] if there is not exactly one output key.
    def check_output_keys
      return unless output_keys.length != 1

      raise Boxcars::ArgumentError, "run not supported when there is not exactly one output key. Got #{output_keys}."
    end
  end
end
