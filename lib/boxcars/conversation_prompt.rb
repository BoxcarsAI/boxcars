# frozen_string_literal: true

module Boxcars
  # used by Boxcars that have engine's to create a conversation prompt.
  class ConversationPrompt < Prompt
    attr_reader :conversation

    # @param conversation [Boxcars::Conversation] The conversation to use for the prompt.
    # @param input_variables [Array<Symbol>] The input vars to use for the prompt. Defaults to [:input]
    # @param other_inputs [Array<Symbol>] The other input vars to use for the prompt. Defaults to []
    # @param output_variables [Array<Symbol>] The output vars to use for the prompt. Defaults to [:output]
    def initialize(conversation:, input_variables: nil, other_inputs: nil, output_variables: nil)
      @conversation = conversation
      super(template: template, input_variables: input_variables, other_inputs: other_inputs, output_variables: output_variables)
    end

    # prompt for chatGPT params
    # @param inputs [Hash] The inputs to use for the prompt.
    # @return [Hash] The formatted prompt.
    def as_messages(inputs)
      conversation.as_messages(inputs)
    end

    # prompt for non chatGPT params
    # @param inputs [Hash] The inputs to use for the prompt.
    # @return [Hash] The formatted prompt.
    def as_prompt(inputs)
      { prompt: conversation.as_prompt(inputs) }
    end

    # tack on the ongoing conversation if present to the prompt
    def with_conversation(conversation)
      return self unless conversation

      new_prompt = dup
      new_prompt.conversation.add_conversation(conversation)
      new_prompt
    end
  end
end
