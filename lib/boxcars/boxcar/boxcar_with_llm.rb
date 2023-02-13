# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # For Boxcars that use an LLM to do their work.
  # @abstract
  class BoxcarWithLLM < Boxcars::Boxcar
    attr_accessor :prompt, :llm, :output_key

    # A Boxcar is a container for a single tool to run.
    # @param prompt [Boxcars::LLMPrompt] The prompt to use for this boxcar with sane defaults.
    # @param name [String] The name of the boxcar. Defaults to classname.
    # @param description [String] A description of the boxcar.
    # @param llm [Boxcars::LLM] The LLM to user for this boxcar. Can be inherited from a conductor if nil.
    def initialize(prompt:, llm:, output_key: "text", name: nil, description: nil)
      @prompt = prompt
      @llm = llm
      @output_key = output_key
      super(name: name, description: description)
    end

    def input_keys
      prompt.input_variables
    end

    def output_keys
      [output_key]
    end

    # Check that all inputs are present.
    def validate_inputs(inputs:)
      missing_keys = input_keys - inputs.keys
      raise Boxcars::ArgumentError, "Missing some input keys: #{missing_keys}" if missing_keys.any?

      inputs
    end

    def validate_outputs(outputs:)
      return if outputs.sort == output_keys.sort

      raise Boxcars::ArgumentError, "Did not get out keys that were expected, got: #{outputs}. Expected: #{output_keys}"
    end

    def generate(input_list:)
      stop = input_list[0][:stop]
      prompts = []
      input_list.each do |inputs|
        new_prompt = prompt.format(**inputs)
        puts "Prompt after formatting:\n#{new_prompt.colorize(:cyan)}"
        prompts.push(new_prompt)
      end
      llm.generate(prompts: prompts, stop: stop)
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

    def check_output_keys
      return unless output_keys.length != 1

      raise Boxcars::ArgumentError, "run not supported when there is not exactly one output key. Got #{output_keys}."
    end

    def run(*args, **kwargs)
      if kwargs.empty?
        raise Boxcars::ArgumentError, "run supports only one positional argument." if args.length != 1

        return do_call(inputs: args[0])[output_keys.first]
      end

      return do_call(**kwargs)[output_keys].first if args.empty?

      raise Boxcars::ArgumentError, "run supported with either positional or keyword arguments but not both. Got args" \
                                    ": #{args} and kwargs: #{kwargs}."
    end

    private

    def our_inputs(inputs)
      if inputs.is_a?(String)
        puts inputs.colorize(:blue)
        # memory = nil # TODO: add memory
        # if memory
        #   # If there are multiple input keys, but some get set by memory so that
        #   # only one is not set, we can still figure out which key it is.
        #   our_input_keys -= memory.keys
        # end
        if input_keys.length != 1
          raise Boxcars::ArgumentError, "A single string input was passed in, but this boxcar expects " \
                                        "multiple inputs (#{input_keys}). When a boxcar expects " \
                                        "multiple inputs, please call it by passing in a hash, eg: `boxcar({'foo': 1, 'bar': 2})`"
        end
        inputs = { input_keys.first => inputs }
      end
      # if memory
      #   external_context = memory.load_memory_variables(inputs)
      #   inputs.merge!(external_context)
      # end
      validate_inputs(inputs: inputs)
    end
  end
end
