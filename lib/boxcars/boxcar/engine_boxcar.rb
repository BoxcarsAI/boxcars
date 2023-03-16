# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # For Boxcars that use an engine to do their work.
  class EngineBoxcar < Boxcar
    attr_accessor :prompt, :engine, :top_k, :stop

    # A Boxcar is a container for a single tool to run.
    # @param prompt [Boxcars::Prompt] The prompt to use for this boxcar with sane defaults.
    # @param engine [Boxcars::Engine] The engine to user for this boxcar. Can be inherited from a train if nil.
    # @param kwargs [Hash] Additional arguments including: name, description, top_k, return_direct, and stop
    def initialize(prompt:, engine: nil, **kwargs)
      @prompt = prompt
      @engine = engine || Boxcars.engine.new
      @top_k = kwargs.delete(:top_k) || 5
      @stop = kwargs.delete(:stop) || ["Answer:"]
      super(**kwargs)
    end

    # input keys for the prompt
    def input_keys
      prompt.input_variables
    end

    # the first input key for the prompt
    def input_key
      input_keys.first
    end

    # output keys
    def output_keys
      prompt.output_variables
    end

    # the first output key
    def output_key
      output_keys.first
    end

    # generate a response from the engine
    # @param input_list [Array<Hash>] A list of hashes of input values to use for the prompt.
    # @param current_conversation [Boxcars::Conversation] Optional ongoing conversation to use for the prompt.
    # @return [Boxcars::EngineResult] The result from the engine.
    def generate(input_list:, current_conversation: nil)
      stop = input_list[0][:stop]
      the_prompt = current_conversation ? prompt.with_conversation(current_conversation) : prompt
      prompts = input_list.map { |inputs| [the_prompt, inputs] }
      engine.generate(prompts: prompts, stop: stop)
    end

    # apply a response from the engine
    # @param input_list [Array<Hash>] A list of hashes of input values to use for the prompt.
    # @param current_conversation [Boxcars::Conversation] Optional ongoing conversation to use for the prompt.
    # @return [Hash] A hash of the output key and the output value.
    def apply(input_list:, current_conversation: nil)
      response = generate(input_list: input_list, current_conversation: current_conversation)
      response.generations.to_h do |generation|
        [output_keys.first, generation[0].text]
      end
    end

    # predict a response from the engine
    # @param current_conversation [Boxcars::Conversation] Optional ongoing conversation to use for the prompt.
    # @param kwargs [Hash] A hash of input values to use for the prompt.
    # @return [String] The output value.
    def predict(current_conversation: nil, **kwargs)
      apply(current_conversation: current_conversation, input_list: [kwargs])[output_keys.first]
    end

    # check that there is exactly one output key
    # @raise [Boxcars::ArgumentError] if there is not exactly one output key.
    def check_output_keys
      return unless output_keys.length != 1

      raise Boxcars::ArgumentError, "not supported when there is not exactly one output key. Got #{output_keys}."
    end

    # call the boxcar
    # @param inputs [Hash] The inputs to the boxcar.
    # @return [Hash] The outputs from the boxcar.
    def call(inputs:)
      # if we get errors back, try predicting again giving the errors with the inputs
      conversation = nil
      answer = nil
      4.times do
        t = predict(current_conversation: conversation, **prediction_variables(inputs)).strip
        answer = get_answer(t)
        if answer.status == :error
          Boxcars.debug "have error, trying again: #{answer.answer}", :red
          conversation ||= Conversation.new
          conversation.add_user(answer.answer)
        else
          Boxcars.debug answer.to_json, :magenta
          return { output_keys.first => answer }
        end
      end
      Boxcars.error answer.to_json, :red
      { output_key => "Error: #{answer}" }
    rescue Boxcars::ConfigurationError => e
      raise e
    rescue Boxcars::Error => e
      Boxcars.error e.message, :red
      { output_key => "Error: #{e.message}" }
    end

    # @param inputs [Hash] The inputs to the boxcar.
    # @return Hash The input variable for this boxcar.
    def prediction_input(inputs)
      { input_key => inputs[input_key] }
    end

    # @return Hash The additional variables for this boxcar.
    def prediction_additional
      { stop: stop, top_k: top_k }
    end

    # @param inputs [Hash] The inputs to the boxcar.
    # @return Hash The variables for this boxcar.
    def prediction_variables(inputs)
      prediction_input(inputs).merge(prediction_additional)
    end
  end
end
