# frozen_string_literal: true

module Boxcars
  # @abstract
  class Boxcar
    attr_reader :name, :description, :return_direct, :parameters

    # A Boxcar is a container for a single tool to run.
    # @param name [String] The name of the boxcar. Defaults to classname.
    # @param description [String] A description of the boxcar.
    # @param return_direct [Boolean] If true, return the output of this boxcar directly, without merging it with the inputs.
    # @param parameters [Hash] The parameters for this boxcar.
    def initialize(description:, name: nil, return_direct: false, parameters: nil)
      @name = name || self.class.name
      @description = description || @name
      @return_direct = return_direct
      @parameters = parameters || { question: { type: :string, description: "the input question", required: true } }
    end

    # Input keys this chain expects.
    def input_keys
      [:question]
    end

    # Output keys this chain expects.
    def output_keys
      [:answer]
    end

    # Check that all inputs are present.
    # @param inputs [Hash] The inputs.
    # @raise [RuntimeError] If the inputs are not the same.
    def validate_inputs(inputs:)
      missing_keys = input_keys - inputs.keys
      raise "Missing some input keys: #{missing_keys}" if missing_keys.any?

      inputs
    end

    # check that all outputs are present
    # @param outputs [Array<String>] The output keys.
    # @raise [RuntimeError] If the outputs are not the same.
    def validate_outputs(outputs:)
      return if (outputs - output_keys - ['log']).empty?

      raise "Did not get output keys that were expected, got: #{outputs}. Expected: #{output_keys}"
    end

    # Run the logic of this chain and return the output.
    def call(inputs:)
      raise NotImplementedError
    end

    # Apply the boxcar to a list of inputs.
    # @param input_list [Array<Hash>] The list of inputs.
    # @return [Array<Boxcars::Boxcar>] The list of outputs.
    def apply(input_list:)
      raise NotImplementedError
    end

    # Get an answer from the boxcar.
    # @param args [Array] The positional arguments to pass to the boxcar.
    # @param kwargs [Hash] The keyword arguments to pass to the boxcar.
    # you can pass one or the other, but not both.
    # @return [String] The answer to the question.
    def run(*args, **kwargs)
      rv = conduct(*args, **kwargs)
      rv = rv[:answer] if rv.is_a?(Hash) && rv.key?(:answer)
      return rv.answer if rv.is_a?(Result)
      return rv[output_keys[0]] if rv.is_a?(Hash)

      rv
    end

    # Get an extended answer from the boxcar.
    # @param args [Array] The positional arguments to pass to the boxcar.
    # @param kwargs [Hash] The keyword arguments to pass to the boxcar.
    # you can pass one or the other, but not both.
    # @return [Boxcars::Result] The answer to the question.
    def conduct(*args, **kwargs)
      Boxcars.info "> Entering #{name}#run", :gray, style: :bold
      rv = depart(*args, **kwargs)
      remember_history(rv)
      Boxcars.info "< Exiting #{name}#run", :gray, style: :bold
      rv
    end

    # helpers for conversation prompt building
    # assistant message
    def self.assi(*strs)
      [:assistant, strs.join]
    end

    # system message
    def self.syst(*strs)
      [:system, strs.join]
    end

    # user message
    def self.user(*strs)
      [:user, strs.join]
    end

    # history entries
    def self.hist
      [:history, ""]
    end

    # save this boxcar to a file
    def save(path:)
      File.write(path, YAML.dump(self))
    end

    # load this boxcar from a file
    # rubocop:disable Security/YAMLLoad
    def load(path:)
      YAML.load(File.read(path))
    end
    # rubocop:enable Security/YAMLLoad

    def schema
      params = parameters.map do |name, info|
        "<param name=#{name.to_s.inspect} data-type=#{info[:type].to_s.inspect} required=\"#{(info[:required] == true)}\" description=#{info[:description].inspect} />"
      end.join("\n")
      <<~SCHEMA.freeze
        <tool name="#{name}" description="#{description}">
          <params>
            #{params}
          </params>
        </tool>
      SCHEMA
    end

    private

    # remember the history of this boxcar. Take the current intermediate steps and
    # create a history that can be used on the next run.
    # @param current_results [Array<Hash>] The current results.
    def remember_history(current_results)
      return unless current_results[:intermediate_steps] && is_a?(Train)

      # insert conversation history into the prompt
      history = []
      history << Boxcar.user(key_and_value_text(question_prefix, current_results[:input]))
      current_results[:intermediate_steps].each do |action, obs|
        if action.is_a?(TrainAction)
          obs = Observation.new(status: :ok, note: obs) if obs.is_a?(String)
          next if obs.status != :ok

          history << Boxcar.assi("#{thought_prefix}#{action.log}", "\n",
                                 key_and_value_text(observation_prefix, obs.note))
        else
          Boxcars.error "Unknown action: #{action}", :red
        end
      end
      final_answer = key_and_value_text(final_answer_prefix, current_results[:output])
      history << Boxcar.assi(
        key_and_value_text(thought_prefix, "I know the final answer\n#{final_answer}\n"))
      prompt.add_history(history)
    end

    # Get an answer from the boxcar.
    def run_boxcar(inputs:, return_only_outputs: false)
      inputs = our_inputs(inputs)
      output = nil
      begin
        output = call(inputs: inputs)
      rescue StandardError => e
        Boxcars.error "Error in #{name} boxcar#call: #{e}\nbt:#{caller[0..5].join("\n   ")}", :red
        raise e
      end
      validate_outputs(outputs: output.keys)
      return output if return_only_outputs

      inputs.merge(output)
    end

    # line up parameters and run boxcar
    def depart(*args, **kwargs)
      if kwargs.empty?
        raise Boxcars::ArgumentError, "run supports only one positional argument." if args.length != 1

        return run_boxcar(inputs: args[0])
      end

      return run_boxcar(inputs: kwargs) if args.empty?

      raise Boxcars::ArgumentError, "run supported with either positional or keyword arguments but not both. Got args" \
                                    ": #{args} and kwargs: #{kwargs}."
    end

    def our_inputs(inputs)
      if inputs.is_a?(String)
        Boxcars.info inputs, :blue # the question
        if input_keys.length != 1
          raise Boxcars::ArgumentError, "A single string input was passed in, but this boxcar expects " \
                                        "multiple inputs (#{input_keys}). When a boxcar expects " \
                                        "multiple inputs, please call it by passing in a hash, eg: `boxcar({'foo': 1, 'bar': 2})`"
        end
        inputs = { input_keys.first => inputs }
      end
      validate_inputs(inputs: inputs)
    end

    # the default answer is the text passed in
    def get_answer(text)
      Result.from_text(text)
    end
  end
end

require "boxcars/observation"
require "boxcars/result"
require "boxcars/boxcar/engine_boxcar"
require "boxcars/boxcar/calculator"
require "boxcars/boxcar/ruby_calculator"
require "boxcars/boxcar/google_search"
require "boxcars/boxcar/url_text"
require "boxcars/boxcar/wikipedia_search"
require "boxcars/boxcar/sql_base"
require "boxcars/boxcar/sql_active_record"
require "boxcars/boxcar/sql_sequel"
require "boxcars/boxcar/swagger"
require "boxcars/boxcar/active_record"
require "boxcars/vector_store"
require "boxcars/vector_search"
require "boxcars/boxcar/vector_answer"
