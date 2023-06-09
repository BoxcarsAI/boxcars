# frozen_string_literal: true

# Agent for the MRKL chain
module Boxcars
  # A Train using the zero-shot react method.
  class ZeroShot < Train
    attr_reader :boxcars, :observation_prefix, :engine_prefix
    attr_accessor :wants_next_actions

    # @param boxcars [Array<Boxcars::Boxcar>] The boxcars to run.
    # @param engine [Boxcars::Engine] The engine to use for this train.
    # @param name [String] The name of the train. Defaults to 'Zero Shot'.
    # @param description [String] The description of the train. Defaults to 'Zero Shot Train'.
    # @param prompt [Boxcars::Prompt] The prompt to use. Defaults to the built-in prompt.
    # @param kwargs [Hash] Additional arguments to pass to the train. wants_next_actions: true
    def initialize(boxcars:, engine: nil, name: 'Zero Shot', description: 'Zero Shot Train', prompt: nil, **kwargs)
      @observation_prefix = 'Observation: '
      @engine_prefix = 'Thought:'
      @wants_next_actions = kwargs.fetch(:wants_next_actions, false)
      prompt ||= my_prompt
      super(engine: engine, boxcars: boxcars, prompt: prompt, name: name, description: description)
    end

    # @return Hash The additional variables for this boxcar.
    def prediction_additional(_inputs)
      { boxcar_names: boxcar_names, boxcar_descriptions: boxcar_descriptions, next_actions: next_actions }.merge super
    end

    # Extract the boxcar and input from the engine output.
    # @param text [String] The output from the engine.
    # @return [Array<Boxcars::Boxcar, String>] The boxcar and input.
    def extract_boxcar_and_input(text)
      get_action_and_input(engine_output: text)
    end

    private

    # the final answer action string
    FINAL_ANSWER_ACTION = "Final Answer:"

    # Parse out the action and input from the engine output.
    # @param engine_output [String] The output from the engine.
    # @return [Array<String>] The action and input.
    def get_action_and_input(engine_output:)
      # NOTE: if you're specifying a custom prompt for the ZeroShotAgent,
      #   you will need to ensure that it meets the following Regex requirements.
      #   The string starting with "Action:" and the following string starting
      #   with "Action Input:" should be separated by a newline.
      if engine_output.include?(FINAL_ANSWER_ACTION)
        answer = engine_output.split(FINAL_ANSWER_ACTION).last.strip
        Result.new(status: :ok, answer: answer, explanation: engine_output)
      else
        # the thought should be the frist line here if it doesn't start with "Action:"
        thought = engine_output.split(/\n+/).reject(&:empty?).first
        Boxcars.debug("Thought: #{thought}", :yellow)
        regex = /Action(?<extra>[\s\d]*): (?<action>.+?)\n+Action Input:(?<action_input>.+)/m
        match = regex.match(engine_output)

        # we have an unexpected output from the engine
        unless match
          return [:error, "You gave me an improperly fomatted answer - try again. For example, if you know the final anwwer, " \
                          "start with #{FINAL_ANSWER_ACTION.inspect}"]
        end

        action = match[:action].strip
        action_input = match[:action_input].strip.delete_prefix('"').delete_suffix('"')
        [action, action_input]
      end
    end

    CTEMPLATE = [
      syst("Answer the following questions as best you can. You have access to the following actions:\n",
           "%<boxcar_descriptions>s\n",
           "Use the following format:\n",
           "Question: the input question you must answer\n",
           "Thought: you should always think about what to do\n",
           "Action: the action to take, should be one from this list: %<boxcar_names>s\n",
           "Action Input: an input question to the action\n",
           "Observation: the result of the action\n",
           "... (this Thought/Action/Action Input/Observation sequence can repeat N times)\n",
           "Thought: I know the final answer\n",
           "Final Answer: the final answer to the original input question\n",
           "%<next_actions>s\n",
           "Remember to start a line with \"Final Answer:\" to give me the final answer.\n",
           "Also make sure to specify a question for the Action Input.\n",
           "Begin!"),
      user("Question: %<input>s"),
      assi("Thought: %<agent_scratchpad>s")
    ].freeze

    def boxcar_names
      @boxcar_names ||= "[#{boxcars.map(&:name).join(', ')}]"
    end

    def boxcar_descriptions
      @boxcar_descriptions ||= boxcars.map { |boxcar| "#{boxcar.name}: #{boxcar.description}" }.join("\n")
    end

    def next_actions
      if wants_next_actions
        "Next Actions: Up to 3 logical suggested next questions for the user to ask after getting this answer.\n"
      else
        ""
      end
    end

    # The prompt to use for the train.
    def my_prompt
      @conversation ||= Conversation.new(lines: CTEMPLATE)
      @my_prompt ||= ConversationPrompt.new(
        conversation: @conversation,
        input_variables: [:input],
        other_inputs: [:boxcar_names, :boxcar_descriptions, :next_actions, :agent_scratchpad],
        output_variables: [:answer])
    end
  end
end
