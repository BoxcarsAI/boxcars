# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # For Boxcars that use an engine to do their work.
  class JSONEngineBoxcar < EngineBoxcar
    # A JSON Engine Boxcar is a container for a single tool to run.
    attr_accessor :wanted_data, :data_description

    # @param prompt [Boxcars::Prompt] The prompt to use for this boxcar with sane defaults.
    # @param wanted_data [String] The data to extract from.
    # @param data_description [String] The description of the data.
    # @param kwargs [Hash] Additional arguments
    def initialize(prompt: nil, wanted_data: nil, data_description: nil, **kwargs)
      @wanted_data = wanted_data || "summarize the pertinent facts from the input data"
      @data_description = data_description || "the input data"
      the_prompt = prompt || default_prompt
      kwargs[:description] ||= "JSON Engine Boxcar"
      super(prompt: the_prompt, **kwargs)
    end

    def default_prompt
      stock_prompt = <<~SYSPR
        I will provide you with %<data_description>s, and your job is to extract information as described below.

        Your Output must be valid JSON with no lead in or post answer text in the output format below:

        Output Format:
          {
            %<wanted_data>s
          }
      SYSPR
      sprompt = stock_prompt % { wanted_data: wanted_data, data_description: data_description }
      ctemplate = [
        Boxcar.syst(sprompt),
        Boxcar.user("%<input>s")
      ]
      conversation = Conversation.new(lines: ctemplate)
      ConversationPrompt.new(conversation:, input_variables: [:input], other_inputs: [], output_variables: [:answer])
    end

    # Parse out the action and input from the engine output.
    # @param engine_output [String] The output from the engine.
    # @return [Result] The result.
    def get_answer(engine_output)
      extract_answer(JSON.parse(engine_output))
    rescue StandardError => e
      Result.from_error("Error: #{e.message}:\n#{engine_output}")
    end

    # get answer from parsed JSON
    # @param data [Hash] The data to extract from.
    # @return [Result] The result.
    def extract_answer(data)
      reply = data

      if reply.present?
        Result.new(status: :ok, answer: reply, explanation: reply)
      else
        # we have an unexpected output from the engine
        Result.new(status: :error, answer: nil,
                   explanation: "You gave me an improperly formatted answer or didn't use proper JSON. I was expecting a valid reply.")
      end
    end
  end
end
