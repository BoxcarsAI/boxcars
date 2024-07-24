# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # For Boxcars that use an engine to do their work.
  class JSONEngineBoxcar < EngineBoxcar
    # A JSON Engine Boxcar is a container for a single tool to run.
    attr_accessor :wanted_data, :data_description, :important, :symbolize

    # @param prompt [Boxcars::Prompt] The prompt to use for this boxcar with sane defaults.
    # @param wanted_data [String] The data to extract from.
    # @param data_description [String] The description of the data.
    # @param important [String] Any important instructions you want to give the LLM.
    # @param kwargs [Hash] Additional arguments
    def initialize(prompt: nil, wanted_data: nil, data_description: nil, important: nil, symbolize: false, **kwargs)
      @wanted_data = wanted_data || "summarize the pertinent facts from the input data"
      @data_description = data_description || "the input data"
      @important = important
      the_prompt = prompt || default_prompt
      kwargs[:description] ||= "JSON Engine Boxcar"
      @symbolize = symbolize
      super(prompt: the_prompt, **kwargs)
    end

    def default_prompt
      stock_prompt = <<~SYSPR
        I will provide you with %<data_description>s.
        Your job is to extract information as described below.

        Your Output must be valid JSON with no lead in or post answer text in the output format below:

        Output Format:
          {
            %<wanted_data>s
          }
      SYSPR
      stock_prompt += "\n\nImportant:\n#{important}\n" if important.present?

      sprompt = format(stock_prompt, wanted_data: wanted_data, data_description: data_description)
      ctemplate = [
        Boxcar.syst(sprompt),
        Boxcar.user("%<input>s")
      ]
      conv = Conversation.new(lines: ctemplate)
      ConversationPrompt.new(conversation: conv, input_variables: [:input], other_inputs: [], output_variables: [:answer])
    end

    # Parse out the action and input from the engine output.
    # @param engine_output [String] The output from the engine.
    # @return [Result] The result.
    def get_answer(engine_output)
      # sometimes the LLM adds text in front of the JSON output, so let's strip it here
      json_start = engine_output.index("{")
      json_end = engine_output.rindex("}")
      extract_answer(JSON.parse(engine_output[json_start..json_end], symbolize_names: symbolize))
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
                   explanation: "You gave me an improperly formatted answer. I was expecting a valid reply.")
      end
    end
  end
end
