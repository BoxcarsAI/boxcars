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

    # compute the prompt parameters with input substitutions (used for chatGPT)
    # @param inputs [Hash] The inputs to use for the prompt.
    # @return [Hash] The formatted prompt { messages: ...}
    def as_prompt(inputs)
      { prompt: format(inputs) }
    end

    # compute the prompt parameters with input substitutions
    # @param inputs [Hash] The inputs to use for the prompt.
    # @return [Hash] The formatted prompt { prompt: "..."}
    def as_messages(inputs)
      { messages: [{ role: :assistant, content: format(inputs) }] }
    end

    # tack on the ongoing conversation if present to the prompt
    def with_conversation(conversation)
      return self unless conversation

      new_prompt = dup
      new_prompt.template += "\n\n#{conversation.message_text}"
      new_prompt
    end

    private

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
  end
end
