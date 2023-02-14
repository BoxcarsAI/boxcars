# frozen_string_literal: true

module Boxcars
  # Conductor's action to take.
  class ConductorAction
    attr_accessor :tool, :tool_input, :log

    def initialize(tool: nil, tool_input: nil, log: nil)
      @tool = tool
      @tool_input = tool_input
      @log = log
    end
  end
end
