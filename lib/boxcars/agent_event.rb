# frozen_string_literal: true

module Boxcars
  # Lightweight immutable event emitted during agent execution.
  # Captures what the agent is doing at each step without affecting execution.
  class AgentEvent
    TYPES = %i[
      agent_start
      llm_call_start
      llm_response
      tool_call_start
      tool_call_blocked
      tool_call_end
      handoff
      agent_complete
      agent_error
    ].freeze

    attr_reader :type, :data, :timestamp, :iteration

    # @param type [Symbol] One of TYPES
    # @param data [Hash] Event-specific payload (frozen on init)
    # @param iteration [Integer] Current agent loop iteration
    def initialize(type:, data: {}, iteration: 0)
      raise ::ArgumentError, "Unknown event type: #{type}" unless TYPES.include?(type)

      @type = type
      @data = data.freeze
      @timestamp = Time.now
      @iteration = iteration
    end
  end
end
