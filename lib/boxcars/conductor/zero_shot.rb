# Agent for the MRKL chain
module Boxcars
  # A Conductor using the zero-shot react method.
  class ZeroShot < Conductor
    attr_reader :boxcars, :observation_prefix, :llm_prefix

    PREFIX = "Answer the following questions as best you can. You have access to the following tools:".freeze
    FORMAT_INSTRUCTIONS = <<~FINPUT.freeze
      Use the following format:

      Question: the input question you must answer
      Thought: you should always think about what to do
      Action: the action to take, should be one of [%<boxcar_names>s]
      Action Input: the input to the action
      Observation: the result of the action
      ... (this Thought/Action/Action Input/Observation can repeat N times)
      Thought: I now know the final answer
      Final Answer: the final answer to the original input question
    FINPUT

    SUFFIX = <<~SINPUT.freeze
      Begin!

      Question: %<input>s
      Thought:%<agent_scratchpad>s
    SINPUT

    def initialize(boxcars:, llm:, name: 'Zero Shot', description: 'Zero Shot Conductor')
      @observation_prefix = 'Observation: '
      @llm_prefix = 'Thought:'
      prompt = self.class.create_prompt(boxcars: boxcars)
      super(llm: llm, boxcars: boxcars, prompt: prompt, name: name, description: description)
    end

    # Create prompt in the style of the zero shot agent.

    #   Args:
    #     boxcars: List of boxcars the agent will have access to, used to format the prompt.
    #     prefix: String to put before the list of boxcars.
    #     suffix: String to put after the list of boxcars.
    #     input_variables: List of input variables the final prompt will expect.

    #   Returns:
    #     A LLMPrompt with the template assembled from the pieces here.

    def self.create_prompt(boxcars:, prefix: PREFIX, suffix: SUFFIX, input_variables: [:input, :agent_scratchpad])
      boxcar_strings = boxcars.map { |boxcar| "#{boxcar.name}: #{boxcar.description}" }.join("\n")
      boxcar_names = boxcars.map(&:name)
      format_instructions = format(FORMAT_INSTRUCTIONS, boxcar_names: boxcar_names.join(", "))
      template = [prefix, boxcar_strings, format_instructions, suffix].join("\n\n")
      LLMPrompt.new(template: template, input_variables: input_variables)
    end

    FINAL_ANSWER_ACTION = "Final Answer:".freeze

    # Parse out the action and input from the LLM output.
    def get_action_and_input(llm_output:)
      # NOTE: if you're specifying a custom prompt for the ZeroShotAgent,
      #   you will need to ensure that it meets the following Regex requirements.
      #   The string starting with "Action:" and the following string starting
      #   with "Action Input:" should be separated by a newline.
      if llm_output.include?(FINAL_ANSWER_ACTION)
        answer = llm_output.split(FINAL_ANSWER_ACTION).last.strip
        ['Final Answer', answer]
      else
        regex = /Action: (.*?)\nAction Input: (.*)/
        match = regex.match(llm_output)
        raise ValueError("Could not parse LLM output: `#{llm_output}`") unless match

        action = match.group(1).strip
        action_input = match.group(2)
        [action, action_input.strip(" ").strip('"')]
      end
    end

    def extract_boxcar_and_input(text)
      get_action_and_input(llm_output: text)
    end
  end
end
