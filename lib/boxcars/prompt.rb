# frozen_string_literal: true

module Boxcars
  # used by Boxcars that have engine's to create a prompt.
  class Prompt
    attr_reader :template, :input_variables, :output_variables

    # @param template [String] The template to use for the prompt.
    # @param input_variables [Array<Symbol>] The input vars to use for the prompt.
    # @param output_variables [Array<Symbol>] The output vars to use for the prompt. Defaults to [:agent_scratchpad]
    def initialize(template:, input_variables:, output_variables: [:agent_scratchpad])
      @template = template
      @input_variables = input_variables
      @output_variables = output_variables
    end

    # format the prompt with the input variables
    def format(inputs)
      @template % inputs
    end

    # check if the template is valid
    def template_is_valid?
      @template.include?("%<input>s") && @template.include?("%<agent_scratchpad>s")
    end

    # create a prompt template from examples
    # @param examples [String] or [Array<String>] The example(s) to use for the template.
    # @param input_variables [Array<Symbol>] The input variables to use for the prompt.
    # @param example_separator [String] The separator to use between the examples. Defaults to "\n\n"
    # @param prefix [String] The prefix to use for the template. Defaults to ""
    def self.from_examples(examples:, suffix:, input_variables:, example_separator: "\n\n", prefix: "")
      template = [prefix, examples, suffix].join(example_separator)
      Prompt.new(template: template, input_variables: input_variables)
    end

    # create a prompt template from a file
    # @param path [String] The path to the file to use for the template.
    # @param input_variables [Array<Symbol>] The input variables to use for the prompt.
    def self.from_file(path:, input_variables:)
      template = File.read(path)
      Prompt.new(template: template, input_variables: input_variables)
    end
  end
end
