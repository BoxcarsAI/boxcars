# frozen_string_literal: true

module Boxcars
  # @abstract
  class Conductor
    attr_reader :llm, :boxcars, :name, :description, :prompt, :llm_boxcar, :return_values

    # A Conductor will use a LLM to run a series of boxcars.
    # @param llm [Boxcars::LLM] The LLM to use for this conductor.
    # @param boxcars [Array<Boxcars::Boxcar>] The boxcars to run.
    # @abstract
    def initialize(llm:, boxcars:, prompt:, name: nil, description: nil)
      @llm = llm
      @boxcars = boxcars
      @prompt = prompt
      @name = name || self.class.name
      @description = description
      @return_values = [:output]
      @llm_boxcar = LLMBoxcar.new(prompt: prompt, llm: llm)
    end

    # Get an answer from the conductor.
    # @param question [String] The question to ask the conductor.
    # @return [String] The answer to the question.
    def run(question)
      raise NotImplementedError
    end

    # Extract the boxcar name and input from the text.
    def extract_boxcar_and_input(text)
    end

    def stop
      ["\n#{observation_prefix}"]
    end

    def construct_scratchpad(intermediate_steps)
      thoughts = ""
      intermediate_steps.each do |action, observation|
        thoughts += action.is_a?(String) ? action : action.log
        thoughts += "\n#{observation_prefix}#{observation}\n#{llm_prefix}"
      end
      thoughts
    end

    def get_next_action(full_inputs)
      full_output = llm_boxcar.predict(**full_inputs)
      parsed_output = extract_boxcar_and_input(full_output)
      while parsed_output.nil?
        full_output = _fix_text(full_output)
        full_inputs[:agent_scratchpad] += full_output
        output = llm_boxcar.predict(**full_inputs)
        full_output += output
        parsed_output = extract_boxcar_and_input(full_output)
      end
      ConductorAction.new(tool: parsed_output[0], tool_input: parsed_output[1], log: full_output)
    end

    # Given input, decided what to do.
    # @param intermediate_steps [Array<Hash>] The intermediate steps taken so far along with observations.
    # @param kwargs [Hash] User inputs.
    # @return [Boxcars::Action] Action specifying what tool to use.
    def plan(intermediate_steps, **kwargs)
      thoughts = construct_scratchpad(intermediate_steps)
      new_inputs = { agent_scratchpad: thoughts, stop: stop }
      full_inputs = kwargs.merge(new_inputs)
      action = get_next_action(full_inputs)
      return ConductorFinish.new({ output: action.tool_input }, log: action.log) if action.tool == finish_tool_name

      action
    end

    # Prepare the agent for new call, if needed
    def prepare_for_new_call
    end

    # Name of the tool to use to finish the chain
    def finish_tool_name
      "Final Answer"
    end

    def input_keys
      # Return the input keys
      list = prompt.input_variables
      list.delete(:agent_scratchpad)
      list
    end

    # Check that all inputs are present.
    def validate_inputs(inputs:)
      missing_keys = input_keys - inputs.keys
      raise "Missing some input keys: #{missing_keys}" if missing_keys.any?
    end

    def validate_prompt(values: Dict)
      prompt = values["llm_chain"].prompt
      unless prompt.input_variables.include?(:agent_scratchpad)
        logger.warning("`agent_scratchpad` should be a variable in prompt.input_variables. Not found, adding it at the end.")
        prompt.input_variables.append(:agent_scratchpad)
        case prompt
        when PromptTemplate
          prompt.template += "\n%<agent_scratchpad>s"
        when FewShotPromptTemplate
          prompt.suffix += "\n%<agent_scratchpad>s"
        else
          raise ValueError("Got unexpected prompt type #{type(prompt)}")
        end
      end
      values
    end

    def return_stopped_response(early_stopping_method, intermediate_steps, **kwargs)
      case early_stopping_method
      when "force"
        ConductorFinish({ output: "Agent stopped due to max iterations." }, "")
      when "generate"
        thoughts = ""
        intermediate_steps.each do |action, observation|
          thoughts += action.log
          thoughts += "\n#{observation_prefix}#{observation}\n#{llm_prefix}"
        end
        thoughts += "\n\nI now need to return a final answer based on the previous steps:"
        new_inputs = { agent_scratchpad: thoughts, stop: _stop }
        full_inputs = kwargs.merge(new_inputs)
        full_output = llm_boxcar.predict(**full_inputs)
        parsed_output = extract_boxcar_and_input(full_output)
        if parsed_output.nil?
          ConductorFinish({ output: full_output }, full_output)
        else
          tool, tool_input = parsed_output
          if tool == finish_tool_name
            ConductorFinish({ output: tool_input }, full_output)
          else
            ConductorFinish({ output: full_output }, full_output)
          end
        end
      else
        raise "early_stopping_method should be one of `force` or `generate`, got #{early_stopping_method}"
      end
    end
  end
end

require "boxcars/conductor/conductor_action"
require "boxcars/conductor/conductor_finish"
require "boxcars/conductor/conductor_executer"
require "boxcars/conductor/zero_shot"
