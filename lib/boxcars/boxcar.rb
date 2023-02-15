# frozen_string_literal: true

module Boxcars
  # @abstract
  class Boxcar
    attr_reader :name, :description, :return_direct

    # A Boxcar is a container for a single tool to run.
    # @param name [String] The name of the boxcar. Defaults to classname.
    # @param description [String] A description of the boxcar.
    # @param return_direct [Boolean] If true, return the output of this boxcar directly, without merging it with the inputs.
    def initialize(description:, name: nil, return_direct: false)
      @name = name || self.class.name
      @description = description
      @return_direct = return_direct
    end

    # Input keys this chain expects.
    def input_keys
      raise NotImplementedError
    end

    # Output keys this chain expects.
    def output_keys
      raise NotImplementedError
    end

    # Check that all inputs are present.
    def validate_inputs(inputs:)
      missing_keys = input_keys - inputs.keys
      raise "Missing some input keys: #{missing_keys}" if missing_keys.any?

      inputs
    end

    def validate_outputs(outputs:)
      return if outputs.sort == output_keys.sort

      raise "Did not get output keys that were expected, got: #{outputs}. Expected: #{output_keys}"
    end

    # Run the logic of this chain and return the output.
    def call(inputs:)
      raise NotImplementedError
    end

    def do_call(inputs:, return_only_outputs: false)
      inputs = our_inputs(inputs)
      output = nil
      begin
        output = call(inputs: inputs)
      rescue StandardError => e
        raise e
      end
      validate_outputs(outputs: output.keys)
      # memory&.save_convext(inputs: inputs, outputs: outputs)
      return output if return_only_outputs

      inputs.merge(output)
    end

    def apply(input_list:)
      input_list.map { |inputs| new(**inputs) }
    end

    # Get an answer from the boxcar.
    # @param question [String] The question to ask the boxcar.
    # @return [String] The answer to the question.
    def run(*args, **kwargs)
      puts "> Enterning #{name} boxcar#run".colorize(:gray, style: :bold)
      rv = if kwargs.empty?
             raise Boxcars::ArgumentError, "run supports only one positional argument." if args.length != 1

             do_call(inputs: args[0])[output_keys.first]
           elsif args.empty?
             do_call(**kwargs)[output_keys].first
           end
      puts "< Exiting #{name} boxcar#run".colorize(:gray, style: :bold)
      return rv

      raise Boxcars::ArgumentError, "run supported with either positional or keyword arguments but not both. Got args" \
                                    ": #{args} and kwargs: #{kwargs}."
    end

    private

    def our_inputs(inputs)
      if inputs.is_a?(String)
        puts inputs.colorize(:blue) # the question
        if input_keys.length != 1
          raise Boxcars::ArgumentError, "A single string input was passed in, but this boxcar expects " \
                                        "multiple inputs (#{input_keys}). When a boxcar expects " \
                                        "multiple inputs, please call it by passing in a hash, eg: `boxcar({'foo': 1, 'bar': 2})`"
        end
        inputs = { input_keys.first => inputs }
      end
      validate_inputs(inputs: inputs)
    end
  end
end

require "boxcars/boxcar/llm_boxcar"
require "boxcars/boxcar/calculator"
require "boxcars/boxcar/serp"
require "boxcars/boxcar/sql"
