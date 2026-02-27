# frozen_string_literal: true

# Agent for the MRKL chain
module Boxcars
  # A Train using the zero-shot react method and only XML in the prompt.
  class XMLZeroShot < XMLTrain
    attr_accessor :wants_next_actions

    # @param boxcars [Array<Boxcars::Boxcar>] The boxcars to run.
    # @param engine [Boxcars::Engine] The engine to use for this train.
    # @param name [String] The name of the train. Defaults to 'Zero Shot'.
    # @param description [String] The description of the train. Defaults to 'Zero Shot Train'.
    # @param prompt [Boxcars::Prompt] The prompt to use. Defaults to the built-in prompt.
    # @param kwargs [Hash] Additional arguments to pass to the train. wants_next_actions: true
    def initialize(boxcars:, engine: nil, name: 'Zero Shot XML', description: 'Zero Shot Train wiht XML', prompt: nil, **kwargs)
      @engine_prefix = ''
      @wants_next_actions = kwargs.fetch(:wants_next_actions, false)
      prompt ||= my_prompt
      super(engine:, boxcars:, prompt:, name:, description:, **kwargs)
    end

    CTEMPLATE = [
      syst("<training>Answer the following questions as best you can. You have access to the following tools for actions:\n",
           "%<boxcars_xml>s",
           "Use the following format making sure all open tags have closing tags:\n",
           " <question>the input question you must answer</question>\n",
           " <thought>you should always think about what to do</thought>\n",
           " <action>the action to take, from this action list above</action>\n",
           " <action_input>input to the action</action_input>\n",
           " <observation>the result of the action</observation>\n",
           " ... (this thought/action/action_input/observation sequence repeats until you know the final answer) ...\n",
           " <thought>I know the final answer</thought>\n",
           " <final_answer>the final answer to the original input question</final_answer>\n",
           "-- FORMAT END -\n",
           "Your answer should always have begin and end tags for each element.\n",
           "Also make sure to specify arguments for the action_input.\n",
           "Finally, if you can deduct the answer from the question or observations, you can ",
           "jump to final_answer and give me the answer.\n",
           "</training>"),
      hist, # insert thoughts here from previous runs
      user("<question>%<input>s</question>"),
      assi("%<agent_scratchpad>s")
    ].freeze

    private

    # The prompt to use for the train.
    def my_prompt
      @conversation ||= Conversation.new(lines: CTEMPLATE)
      @my_prompt ||= ConversationPrompt.new(
        conversation: @conversation,
        input_variables: [:input],
        other_inputs: [:boxcars_xml, :next_actions, :agent_scratchpad],
        output_variables: [:answer])
    end
  end
end
