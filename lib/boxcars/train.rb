# frozen_string_literal: true

module Boxcars
  # @abstract
  class Train < EngineBoxcar
    attr_reader :engine, :boxcars, :name, :description, :prompt, :return_values, :return_intermediate_steps,
                :max_iterations, :early_stopping_method

    # A Train will use a engine to run a series of boxcars.
    # @param engine [Boxcars::Engine] The engine to use for this train.
    # @param boxcars [Array<Boxcars::Boxcar>] The boxcars to run.
    # @param prompt [String] The prompt to use.
    # @abstract
    def initialize(boxcars:, prompt:, engine: nil, **kwargs)
      @boxcars = boxcars
      @name = name || self.class.name
      @return_values = [:output]
      @return_intermediate_steps = kwargs[:return_intermediate_steps] || false
      @max_iterations = kwargs[:max_iterations]
      @early_stopping_method = kwargs[:early_stopping_method] || "force"

      super(prompt: prompt, engine: engine, name: kwargs[:name], description: kwargs[:description])
    end

    # Extract the boxcar name and input from the text.
    # @param text [String] The text to extract from.
    def extract_boxcar_and_input(text)
    end

    # the stop strings list
    def stop
      ["\n#{observation_prefix}"]
    end

    # build the scratchpad for the engine
    # @param intermediate_steps [Array] The intermediate steps to build the scratchpad from.
    # @return [String] The scratchpad.
    def construct_scratchpad(intermediate_steps)
      thoughts = ""
      intermediate_steps.each do |action, observation|
        thoughts += action.is_a?(String) ? action : action.log
        thoughts += "\n#{observation_prefix}#{observation}\n#{engine_prefix}"
      end
      thoughts
    end

    # determine the next action
    # @param full_inputs [Hash] The inputs to the engine.
    # @return [Boxcars::Action] The next action.
    def get_next_action(full_inputs)
      full_output = predict(**full_inputs)
      parsed_output = extract_boxcar_and_input(full_output)
      while parsed_output.nil?
        full_output = _fix_text(full_output)
        full_inputs[:agent_scratchpad] += full_output
        output = predict(**full_inputs)
        full_output += output
        parsed_output = extract_boxcar_and_input(full_output)
      end
      TrainAction.new(boxcar: parsed_output[0], boxcar_input: parsed_output[1], log: full_output)
    end

    # Given input, decided what to do.
    # @param intermediate_steps [Array<Hash>] The intermediate steps taken so far along with observations.
    # @param kwargs [Hash] User inputs.
    # @return [Boxcars::Action] Action specifying what boxcar to use.
    def plan(intermediate_steps, **kwargs)
      thoughts = construct_scratchpad(intermediate_steps)
      new_inputs = { agent_scratchpad: thoughts, stop: stop }
      full_inputs = kwargs.merge(new_inputs)
      action = get_next_action(full_inputs)
      return TrainFinish.new({ output: action.boxcar_input }, log: action.log) if action.boxcar == finish_boxcar_name

      action
    end

    # Prepare the agent for new call, if needed
    def prepare_for_new_call
    end

    # Name of the boxcar to use to finish the chain
    def finish_boxcar_name
      "Final Answer"
    end

    # the input keys
    # @return [Array<Symbol>] The input keys.
    def input_keys
      list = prompt.input_variables
      list.delete(:agent_scratchpad)
      list
    end

    # the output keys
    def output_keys
      return return_values + ["intermediate_steps"] if return_intermediate_steps

      return_values
    end

    # should we continue to run?
    # @param iterations [Integer] The number of iterations.
    # @return [Boolean] Whether to continue.
    def should_continue?(iterations)
      return true if max_iterations.nil?

      iterations < max_iterations
    end

    # handler before returning
    # @param output [Boxcars::TrainFinish] The output.
    # @param intermediate_steps [Array<Hash>] The intermediate steps.
    # @return [Hash] The final output.
    def pre_return(output, intermediate_steps)
      puts output.log.colorize(:yellow)
      final_output = output.return_values
      final_output["intermediate_steps"] = intermediate_steps if return_intermediate_steps
      final_output
    end

    # the prefix for the engine
    # @param return_direct [Boolean] Whether to return directly.
    # @return [String] The prefix.
    def engine_prefix(return_direct)
      return_direct ? "" : engine_prefix
    end

    # validate the prompt
    # @param values [Hash] The values to validate.
    # @return [Hash] The validated values.
    # @raise [RuntimeError] If the prompt is invalid.
    def validate_prompt(values:)
      prompt = values["engine_chain"].prompt
      unless prompt.input_variables.include?(:agent_scratchpad)
        logger.warning("`agent_scratchpad` should be a variable in prompt.input_variables. Not found, adding it at the end.")
        prompt.input_variables.append(:agent_scratchpad)
        case prompt
        when Prompt
          prompt.template += "\n%<agent_scratchpad>s"
        # when FewShotPromptTemplate
        #   prompt.suffix += "\n%<agent_scratchpad>s"
        else
          raise ValueError, "Got unexpected prompt type #{type(prompt)}"
        end
      end
      values
    end

    # get the stopped response
    # @param early_stopping_method [String] The early stopping method.
    # @param intermediate_steps [Array] The intermediate steps.
    # @param kwargs [Hash] extra keword arguments.
    # @return [Boxcars::Action] The action to take.
    def return_stopped_response(early_stopping_method, intermediate_steps, **kwargs)
      case early_stopping_method
      when "force"
        TrainFinish({ output: "Agent stopped due to max iterations." }, "")
      when "generate"
        thoughts = ""
        intermediate_steps.each do |action, observation|
          thoughts += action.log
          thoughts += "\n#{observation_prefix}#{observation}\n#{engine_prefix}"
        end
        thoughts += "\n\nI now need to return a final answer based on the previous steps:"
        new_inputs = { agent_scratchpad: thoughts, stop: _stop }
        full_inputs = kwargs.merge(new_inputs)
        full_output = predict(**full_inputs)
        parsed_output = extract_boxcar_and_input(full_output)
        if parsed_output.nil?
          TrainFinish({ output: full_output }, full_output)
        else
          boxcar, boxcar_input = parsed_output
          if boxcar == finish_boxcar_name
            TrainFinish({ output: boxcar_input }, full_output)
          else
            TrainFinish({ output: full_output }, full_output)
          end
        end
      else
        raise "early_stopping_method should be one of `force` or `generate`, got #{early_stopping_method}"
      end
    end

    # execute the train train
    # @param inputs [Hash] The inputs.
    # @return [Hash] The output.
    def call(inputs:)
      prepare_for_new_call
      name_to_boxcar_map = boxcars.to_h { |boxcar| [boxcar.name, boxcar] }
      intermediate_steps = []
      iterations = 0
      while should_continue?(iterations)
        output = plan(intermediate_steps, **inputs)
        return pre_return(output, intermediate_steps) if output.is_a?(TrainFinish)

        if (boxcar = name_to_boxcar_map[output.boxcar])
          begin
            observation = boxcar.run(output.boxcar_input)
            return_direct = boxcar.return_direct
          rescue StandardError => e
            puts "Error in #{boxcar.name} boxcar#call: #{e}".colorize(:red)
            raise e
          end
        else
          observation = "#{output.boxcar} is not a valid boxcar, try another one."
          return_direct = false
        end
        puts "Observation: #{observation}".colorize(:green)
        intermediate_steps.append([output, observation])
        if return_direct
          output = TrainFinish.new({ return_values[0] => observation }, "")
          return pre_return(output, intermediate_steps)
        end
        iterations += 1
      end
      output = return_stopped_response(early_stopping_method, intermediate_steps, **inputs)
      pre_return(output, intermediate_steps)
    end
  end
end

require "boxcars/train/train_action"
require "boxcars/train/train_finish"
require "boxcars/train/zero_shot"
