# frozen_string_literal: true

module Boxcars
  # Orchestrator that follows agent-to-agent handoffs.
  #
  # Starting from a given agent, runs the agent and follows any handoff chain
  # until an agent completes without a handoff or the max_handoffs limit is reached.
  class AgentRunner
    attr_reader :starting_agent, :max_handoffs

    # @param starting_agent [Boxcars::StationAgent] The first agent to run
    # @param max_handoffs [Integer] Maximum number of handoffs before stopping (default: 10)
    def initialize(starting_agent:, max_handoffs: 10)
      @starting_agent = starting_agent
      @max_handoffs = max_handoffs
    end

    # Run the agent chain starting from the starting_agent.
    # @param input [String] The user input/question
    # @return [Hash] { answer: String, handoff_chain: Array<Hash> }
    def run(input)
      current_agent = starting_agent
      handoff_chain = []
      handoffs_remaining = max_handoffs

      loop do
        result = current_agent.conduct(input)
        handoff = result.respond_to?(:output_for) ? result.output_for(:handoff) : result[:handoff]

        unless handoff
          answer = extract_answer(result, current_agent)
          return { answer: answer, handoff_chain: handoff_chain }
        end

        if handoffs_remaining <= 0
          return {
            answer: "Agent stopped due to max handoffs (#{max_handoffs}).",
            handoff_chain: handoff_chain
          }
        end

        handoff_chain << { from: current_agent.name, to: handoff[:agent].name, reason: handoff[:reason] }
        current_agent = handoff[:agent]
        handoffs_remaining -= 1
      end
    end

    # Run the agent chain while streaming events.
    # @param input [String] The user input/question
    # @yield [AgentEvent] Each lifecycle event from every agent in the chain
    # @return [Hash] { answer: String, handoff_chain: Array<Hash> } when block given
    # @return [Enumerator<AgentEvent>] when no block given
    def run_stream(input, &block)
      return Enumerator.new { |y| run_stream(input) { |event| y << event } } unless block

      current_agent = starting_agent
      handoff_chain = []
      handoffs_remaining = max_handoffs

      loop do
        result = current_agent.run_stream(input, &block)
        handoff = result.respond_to?(:output_for) ? result.output_for(:handoff) : result[:handoff]

        unless handoff
          answer = extract_answer(result, current_agent)
          return { answer: answer, handoff_chain: handoff_chain }
        end

        if handoffs_remaining <= 0
          return {
            answer: "Agent stopped due to max handoffs (#{max_handoffs}).",
            handoff_chain: handoff_chain
          }
        end

        handoff_chain << { from: current_agent.name, to: handoff[:agent].name, reason: handoff[:reason] }
        current_agent = handoff[:agent]
        handoffs_remaining -= 1
      end
    end

    private

    def extract_answer(result, agent)
      boxcars_result = Result.extract(result)
      return boxcars_result.answer if boxcars_result

      if result.respond_to?(:output_for)
        result.output_for(agent.output_keys.first) || result.output_for(:output)
      elsif result.is_a?(Hash)
        result[agent.output_keys.first] || result[:output]
      end
    end
  end
end
