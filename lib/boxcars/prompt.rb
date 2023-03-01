# frozen_string_literal: true

module Boxcars
  # used by Boxcars that have engine's to create a prompt.
  class Prompt
    attr_reader :template, :input_variables, :other_inputs, :output_variables

    # @param template [String] The template to use for the prompt.
    # @param input_variables [Array<Symbol>] The input vars to use for the prompt. Defaults to [:input]
    # @param other_inputs [Array<Symbol>] The other input vars to use for the prompt. Defaults to []
    # @param output_variables [Array<Symbol>] The output vars to use for the prompt. Defaults to [:output]
    def initialize(template:, input_variables: nil, other_inputs: nil, output_variables: nil)
      @template = template
      @input_variables = input_variables || [:input]
      @other_inputs = other_inputs || []
      @output_variables = output_variables || [:output]
    end

    # format the prompt with the input variables
    # @param inputs [Hash] The inputs to use for the prompt.
    # @return [String] The formatted prompt.
    # @raise [Boxcars::KeyError] if the template has extra keys.
    def format(inputs)
      @template % inputs
    rescue ::KeyError => e
      first_line = e.message.to_s.split("\n").first
      Boxcars.error "Missing prompt input key: #{first_line}"
      raise KeyError, "Prompt format error: #{first_line}"
    end

    # check if the template is valid
    def template_is_valid?
      all_vars = (input_variables + other_inputs + output_variables).sort
      template_vars = @template.scan(/%<(\w+)>s/).flatten.map(&:to_sym).sort
      all_vars == template_vars
    end

    # missing variables in the template
    def missing_variables?(inputs)
      input_vars = [input_variables, other_inputs].flatten.sort
      return if inputs.keys.sort == input_vars

      raise ArgumentError, "Missing expected input keys, got: #{inputs.keys}. Expected: #{input_vars}"
    end

    # create a prompt template from examples
    # @param examples [String] or [Array<String>] The example(s) to use for the template.
    # @param input_variables [Array<Symbol>] The input variables to use for the prompt.
    # @param example_separator [String] The separator to use between the examples. Defaults to "\n\n"
    # @param prefix [String] The prefix to use for the template. Defaults to ""
    def self.from_examples(examples:, suffix:, input_variables:, example_separator: "\n\n", prefix: "", **kwargs)
      template = [prefix, examples, suffix].join(example_separator)
      other_inputs = kwargs[:other_inputs] || []
      output_variables = kwargs[:output_variables] || [:output]
      Prompt.new(template: template, input_variables: input_variables, other_inputs: other_inputs,
                 output_variables: output_variables)
    end

    # create a prompt template from a file
    # @param path [String] The path to the file to use for the template.
    # @param input_variables [Array<Symbol>] The input variables to use for the prompt. Defaults to [:input]
    # @param output_variables [Array<Symbol>] The output variables to use for the prompt. Defaults to [:output]
    def self.from_file(path:, input_variables: nil, other_inputs: nil, output_variables: nil)
      template = File.read(path)
      Prompt.new(template: template, input_variables: input_variables, other_inputs: other_inputs,
                 output_variables: output_variables)
    end
  end
end
