# frozen_string_literal: true

module Boxcars
  # used by Boxcars to create a prompt.
  class PromptTemplate
    attr_reader :template, :input_variables, :output_variables, :prompt_type

    # @param template [String] The template to use for the prompt.
    # @param input_variables [Array<Symbol>] The input vars to use for the prompt.
    # @param output_variables [Array<Symbol>] The output vars to use for the prompt. Defaults to [:agent_scratchpad]
    # @param prompt_type [String] The prompt type to use for the prompt. Defaults to "prompt"
    def initialize(template:, input_variables:, output_variables: [:agent_scratchpad], prompt_type: "prompt")
      @template = template
      @input_variables = input_variables
      @output_variables = output_variables
      @prompt_type = prompt_type
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
      PromptTemplate.new(template: template, input_variables: input_variables)
    end

    # create a prompt template from a file
    # @param path [String] The path to the file to use for the template.
    # @param input_variables [Array<Symbol>] The input variables to use for the prompt.
    # @param prompt_type [String] The prompt type to use for the prompt. Defaults to "prompt"
    def self.from_file(path:, input_variables:, prompt_type: "prompt")
      template = File.read(path)
      PromptTemplate.new(template: template, input_variables: input_variables, prompt_type: prompt_type)
    end
  end
end
