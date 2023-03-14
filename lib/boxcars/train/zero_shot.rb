# frozen_string_literal: true

# Agent for the MRKL chain
module Boxcars
  # A Train using the zero-shot react method.
  class ZeroShot < Train
    attr_reader :boxcars, :observation_prefix, :engine_prefix

    # @param boxcars [Array<Boxcars::Boxcar>] The boxcars to run.
    # @param engine [Boxcars::Engine] The engine to use for this train.
    # @param name [String] The name of the train. Defaults to 'Zero Shot'.
    # @param description [String] The description of the train. Defaults to 'Zero Shot Train'.
    # @param prompt [Boxcars::Prompt] The prompt to use. Defaults to the built-in prompt.
    def initialize(boxcars:, engine: nil, name: 'Zero Shot', description: 'Zero Shot Train', prompt: nil)
      @observation_prefix = 'Observation: '
      @engine_prefix = 'Thought:'
      prompt ||= my_prompt
      super(engine: engine, boxcars: boxcars, prompt: prompt, name: name, description: description)
    end

    # @return Hash The additional variables for this boxcar.
    def prediction_additional
      { boxcar_names: boxcar_names, boxcar_descriptions: boxcar_descriptions }.merge super
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
        Boxcars.debug("Though: #{thought}", :cyan)
        regex = /Action: (?<action>.*)\nAction Input: (?<action_input>.*)/
        match = regex.match(engine_output)
        # TODO: this should return an error to the results that can be used for corrections
        raise ValueError, "Could not parse engine output: #{engine_output}" unless match

        action = match[:action].strip
        action_input = match[:action_input].strip.delete_prefix('"').delete_suffix('"')
        [action, action_input]
      end
    end

    CTEMPLATE = [
      [:system, "Answer the following questions as best you can. You have access to the following actions:\n" \
                "%<boxcar_descriptions>s"],
      [:system, "Use the following format:\n" \
                "Question: the input question you must answer\n" \
                "Thought: you should always think about what to do\n" \
                "Action: the action to take, should be one of [%<boxcar_names>s]\n" \
                "Action Input: the input to the action\n" \
                "Observation: the result of the action\n" \
                "... (this Thought/Action/Action Input/Observation sequence can repeat N times)\n" \
                "Thought: I now know the final answer\n" \
                "Final Answer: the final answer to the original input question\n" \
                "Next Actions: If you have them, up to 3 suggested actions for the user to take after getting this answer.\n" \
                "Begin!"],
      [:user, "Question: %<input>s"],
      [:assistant, "Thought: %<agent_scratchpad>s"]
    ].freeze

    def boxcar_names
      @boxcar_names ||= boxcars.map(&:name)
    end

    def boxcar_descriptions
      @boxcar_descriptions ||= boxcars.map { |boxcar| "#{boxcar.name}: #{boxcar.description}" }.join("\n")
    end

    # The prompt to use for the train.
    def my_prompt
      @conversation ||= Conversation.new(lines: CTEMPLATE)
      @my_prompt ||= ConversationPrompt.new(
        conversation: @conversation,
        input_variables: [:input],
        other_inputs: [:boxcar_names, :boxcar_descriptions, :agent_scratchpad],
        output_variables: [:answer])
    end
  end
end
