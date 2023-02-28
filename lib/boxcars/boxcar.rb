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
      @description = description || @name
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
    # @param inputs [Hash] The inputs.
    # @raise [RuntimeError] If the inputs are not the same.
    def validate_inputs(inputs:)
      missing_keys = input_keys - inputs.keys
      raise "Missing some input keys: #{missing_keys}" if missing_keys.any?

      inputs
    end

    # check that all outputs are present
    # @param outputs [Array<String>] The output keys.
    # @raise [RuntimeError] If the outputs are not the same.
    def validate_outputs(outputs:)
      return if outputs.sort == output_keys.sort

      raise "Did not get output keys that were expected, got: #{outputs}. Expected: #{output_keys}"
    end

    # Run the logic of this chain and return the output.
    def call(inputs:)
      raise NotImplementedError
    end

    # Apply the boxcar to a list of inputs.
    # @param input_list [Array<Hash>] The list of inputs.
    # @return [Array<Boxcars::Boxcar>] The list of outputs.
    def apply(input_list:)
      raise NotImplementedError
    end

    # Get an answer from the boxcar.
    # @param args [Array] The positional arguments to pass to the boxcar.
    # @param kwargs [Hash] The keyword arguments to pass to the boxcar.
    # you can pass one or the other, but not both.
    # @return [String] The answer to the question.
    def run(*args, **kwargs)
      Boxcars.info "> Entering #{name}#run", :gray, style: :bold
      rv = do_run(*args, **kwargs)
      Boxcars.info "< Exiting #{name}#run", :gray, style: :bold
      rv
    end

    private

    # Get an answer from the boxcar.
    def do_call(inputs:, return_only_outputs: false)
      inputs = our_inputs(inputs)
      output = nil
      begin
        output = call(inputs: inputs)
      rescue StandardError => e
        Boxcars.error "Error in #{name} boxcar#call: #{e}", :red
        raise e
      end
      validate_outputs(outputs: output.keys)
      # memory&.save_convext(inputs: inputs, outputs: outputs)
      return output if return_only_outputs

      inputs.merge(output)
    end

    def do_run(*args, **kwargs)
      if kwargs.empty?
        raise Boxcars::ArgumentError, "run supports only one positional argument." if args.length != 1

        return do_call(inputs: args[0])[output_keys.first]
      end
      return do_call(**kwargs)[output_keys].first if args.empty?

      raise Boxcars::ArgumentError, "run supported with either positional or keyword arguments but not both. Got args" \
                                    ": #{args} and kwargs: #{kwargs}."
    end

    def our_inputs(inputs)
      if inputs.is_a?(String)
        Boxcars.info inputs, :blue # the question
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

require "boxcars/boxcar/engine_boxcar"
require "boxcars/boxcar/calculator"
require "boxcars/boxcar/google_search"
require "boxcars/boxcar/sql"
require "boxcars/boxcar/active_record"
