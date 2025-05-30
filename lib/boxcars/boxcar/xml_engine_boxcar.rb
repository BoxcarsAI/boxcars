# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # For Boxcars that use an engine to do their work.
  class XMLEngineBoxcar < EngineBoxcar
    # An XML Engine Boxcar is a container for a single tool to run.

    # Parse out the action and input from the engine output.
    # @param engine_output [String] The output from the engine.
    # @return [Array<String>] The action and input.
    def get_answer(engine_output)
      xn_get_answer(XNode.from_xml(engine_output))
    rescue StandardError => e
      Result.from_error("Error: #{e.message}:\n#{engine_output}")
    end

    # get answer an XNode
    # @param xnode [XNode] The XNode to use.
    # @return [Array<String, String>] The action and input.
    def xn_get_answer(xnode)
      reply = xnode.xtext("//reply")

      if reply && !reply.to_s.strip.empty?
        Result.new(status: :ok, answer: reply, explanation: reply)
      else
        # we have an unexpected output from the engine
        Result.new(status: :error, answer: nil,
                   explanation: "You gave me an improperly formatted answer or didn't use tags. I was expecting a reply.")
      end
    end
  end
end
