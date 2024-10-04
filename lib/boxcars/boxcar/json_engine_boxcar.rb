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
    # @param symbolize [Boolean] Symbolize the JSON results if true
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
      json_string = extract_json(engine_output)
      reply = JSON.parse(json_string, symbolize_names: symbolize)
      Result.new(status: :ok, answer: reply, explanation: reply)
    rescue JSON::ParserError => e
      Boxcars.debug "JSON: #{engine_output}", :red
      Result.from_error("JSON parsing error: #{e.message}")
    rescue StandardError => e
      Result.from_error("Unexpected error: #{e.message}")
    end

    # get answer from parsed JSON
    # @param data [Hash] The data to extract from.
    # @return [Result] The result.
    def extract_answer(data)
      reply = data
      Result.new(status: :ok, answer: reply, explanation: reply)
    end

    private

    def extract_json(text)
      # Escape control characters (U+0000 to U+001F)
      text = text.gsub(/[\u0000-\u001F]/, '')
      # first strip hidden characters
      # text = text.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')

      # sometimes the LLM adds text in front of the JSON output, so let's strip it here
      json_start = text.index("{")
      json_end = text.rindex("}")
      text[json_start..json_end]
    end

    def extract_json2(text)
      # Match the outermost JSON object
      match = text.match(/\{(?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*\}/)
      raise StandardError, "No valid JSON object found in the output" unless match

      match[0]
    end
  end
end
