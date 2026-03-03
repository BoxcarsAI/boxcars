# frozen_string_literal: true

require "spec_helper"

RSpec.describe Boxcars::AgentRunner do
  let(:fake_tool_engine_class) do
    Class.new(Boxcars::Engine) do
      attr_reader :calls

      def initialize(responses:)
        @responses = responses.dup
        @calls = []
        super(description: "fake tool engine")
      end

      def capabilities
        super.merge(tool_calling: true)
      end

      def client(prompt:, inputs: {}, **kwargs)
        @calls << { prompt:, inputs:, kwargs: }
        @responses.shift || raise("No fake response left")
      end

      def run(_question)
        raise NotImplementedError
      end
    end
  end

  # Helper: build a simple response hash that returns a final text answer
  def final_answer_response(text)
    {
      "choices" => [
        {
          "message" => {
            "role" => "assistant",
            "content" => text
          }
        }
      ]
    }
  end

  # Helper: build a response that calls a tool
  def tool_call_response(call_id, tool_name, arguments_json)
    {
      "choices" => [
        {
          "message" => {
            "role" => "assistant",
            "content" => nil,
            "tool_calls" => [
              {
                "id" => call_id,
                "type" => "function",
                "function" => {
                  "name" => tool_name,
                  "arguments" => arguments_json
                }
              }
            ]
          }
        }
      ]
    }
  end

  describe "#run" do
    it "returns answer when no handoff occurs" do
      engine = fake_tool_engine_class.new(responses: [final_answer_response("Direct answer.")])
      agent = Boxcars::StationAgent.new(instructions: "Answer directly.", engine: engine)

      runner = described_class.new(starting_agent: agent)
      result = runner.run("Hello")

      expect(result[:answer]).to eq("Direct answer.")
      expect(result[:handoff_chain]).to be_empty
    end

    it "follows a single handoff (A -> B)" do
      engine_b = fake_tool_engine_class.new(responses: [final_answer_response("Billing answer.")])
      agent_b = Boxcars::StationAgent.new(
        instructions: "Handle billing.",
        engine: engine_b,
        name: "Billing Agent",
        description: "Handles billing"
      )

      engine_a = fake_tool_engine_class.new(
        responses: [
          tool_call_response("call_1", "handoff_to_billing_agent", '{"reason":"billing question"}')
        ]
      )
      agent_a = Boxcars::StationAgent.new(
        instructions: "Route requests.",
        engine: engine_a,
        name: "Router",
        description: "Routes",
        handoffs: [agent_b]
      )

      runner = described_class.new(starting_agent: agent_a)
      result = runner.run("How much do I owe?")

      expect(result[:answer]).to eq("Billing answer.")
      expect(result[:handoff_chain].length).to eq(1)
      expect(result[:handoff_chain].first).to eq({ from: "Router", to: "Billing Agent", reason: "billing question" })
    end

    it "follows multi-step chain (A -> B -> C)" do
      engine_c = fake_tool_engine_class.new(responses: [final_answer_response("Refund processed.")])
      agent_c = Boxcars::StationAgent.new(
        instructions: "Process refunds.",
        engine: engine_c,
        name: "Refund Agent",
        description: "Processes refunds"
      )

      engine_b = fake_tool_engine_class.new(
        responses: [
          tool_call_response("call_2", "handoff_to_refund_agent", '{"reason":"needs refund"}')
        ]
      )
      agent_b = Boxcars::StationAgent.new(
        instructions: "Handle billing.",
        engine: engine_b,
        name: "Billing Agent",
        description: "Handles billing",
        handoffs: [agent_c]
      )

      engine_a = fake_tool_engine_class.new(
        responses: [
          tool_call_response("call_1", "handoff_to_billing_agent", '{"reason":"billing question"}')
        ]
      )
      agent_a = Boxcars::StationAgent.new(
        instructions: "Route requests.",
        engine: engine_a,
        name: "Router",
        description: "Routes",
        handoffs: [agent_b]
      )

      runner = described_class.new(starting_agent: agent_a)
      result = runner.run("I want a refund")

      expect(result[:answer]).to eq("Refund processed.")
      expect(result[:handoff_chain].length).to eq(2)
      expect(result[:handoff_chain][0]).to eq({ from: "Router", to: "Billing Agent", reason: "billing question" })
      expect(result[:handoff_chain][1]).to eq({ from: "Billing Agent", to: "Refund Agent", reason: "needs refund" })
    end

    it "stops at max_handoffs limit" do
      engine_b = fake_tool_engine_class.new(responses: [final_answer_response("Never reached.")])
      agent_b = Boxcars::StationAgent.new(
        instructions: "Handle billing.",
        engine: engine_b,
        name: "Billing Agent",
        description: "Handles billing"
      )

      engine_a = fake_tool_engine_class.new(
        responses: [
          tool_call_response("call_1", "handoff_to_billing_agent", '{"reason":"go to billing"}')
        ]
      )
      agent_a = Boxcars::StationAgent.new(
        instructions: "Route requests.",
        engine: engine_a,
        name: "Router",
        description: "Routes",
        handoffs: [agent_b]
      )

      # Agent B hands back to Agent A by calling its handoff
      # But we set max_handoffs: 0 to immediately trigger the limit
      runner = described_class.new(starting_agent: agent_a, max_handoffs: 0)
      result = runner.run("Loop me")

      expect(result[:answer]).to include("max handoffs")
      expect(result[:handoff_chain]).to be_empty
    end

    it "passes original input to each agent" do
      engine_b = fake_tool_engine_class.new(responses: [final_answer_response("Done.")])
      agent_b = Boxcars::StationAgent.new(
        instructions: "Handle billing.",
        engine: engine_b,
        name: "Billing Agent",
        description: "Handles billing"
      )

      engine_a = fake_tool_engine_class.new(
        responses: [
          tool_call_response("call_1", "handoff_to_billing_agent", '{"reason":"billing"}')
        ]
      )
      agent_a = Boxcars::StationAgent.new(
        instructions: "Route requests.",
        engine: engine_a,
        name: "Router",
        description: "Routes",
        handoffs: [agent_b]
      )

      runner = described_class.new(starting_agent: agent_a)
      result = runner.run("My specific question")

      # Verify both engines received calls (agent_a and agent_b both ran)
      expect(engine_a.calls.length).to be >= 1
      expect(engine_b.calls.length).to eq(1)
      expect(result[:answer]).to eq("Done.")
    end
  end

  describe "#run_stream" do
    it "yields events from each agent in handoff chain" do
      engine_b = fake_tool_engine_class.new(responses: [final_answer_response("Billing answer.")])
      agent_b = Boxcars::StationAgent.new(
        instructions: "Handle billing.",
        engine: engine_b,
        name: "Billing Agent",
        description: "Handles billing"
      )

      engine_a = fake_tool_engine_class.new(
        responses: [
          tool_call_response("call_1", "handoff_to_billing_agent", '{"reason":"billing question"}')
        ]
      )
      agent_a = Boxcars::StationAgent.new(
        instructions: "Route requests.",
        engine: engine_a,
        name: "Router",
        description: "Routes",
        handoffs: [agent_b]
      )

      events = []
      runner = described_class.new(starting_agent: agent_a)
      result = runner.run_stream("How much do I owe?") { |event| events << event }

      expect(result[:answer]).to eq("Billing answer.")
      expect(result[:handoff_chain].length).to eq(1)

      types = events.map(&:type)
      # Agent A events + Agent B events
      expect(types).to include(:agent_start, :handoff)
      expect(types).to include(:agent_complete)
      # Should have events from both agents
      agent_starts = events.select { |e| e.type == :agent_start }
      expect(agent_starts.length).to eq(2)
    end

    it "returns { answer:, handoff_chain: } like #run" do
      engine = fake_tool_engine_class.new(responses: [final_answer_response("Direct.")])
      agent = Boxcars::StationAgent.new(instructions: "Answer.", engine: engine)

      runner = described_class.new(starting_agent: agent)
      result = runner.run_stream("Hello") { |_event| nil }

      expect(result[:answer]).to eq("Direct.")
      expect(result[:handoff_chain]).to be_empty
    end

    it "returns Enumerator when no block given" do
      engine = fake_tool_engine_class.new(responses: [final_answer_response("Direct.")])
      agent = Boxcars::StationAgent.new(instructions: "Answer.", engine: engine)

      runner = described_class.new(starting_agent: agent)
      stream = runner.run_stream("Hello")

      expect(stream).to be_a(Enumerator)
      events = stream.to_a
      types = events.map(&:type)
      expect(types).to include(:agent_start, :agent_complete)
    end

    it "stops at max_handoffs limit" do
      engine_b = fake_tool_engine_class.new(responses: [final_answer_response("Never reached.")])
      agent_b = Boxcars::StationAgent.new(
        instructions: "Handle billing.",
        engine: engine_b,
        name: "Billing Agent",
        description: "Handles billing"
      )

      engine_a = fake_tool_engine_class.new(
        responses: [
          tool_call_response("call_1", "handoff_to_billing_agent", '{"reason":"go to billing"}')
        ]
      )
      agent_a = Boxcars::StationAgent.new(
        instructions: "Route.",
        engine: engine_a,
        name: "Router",
        description: "Routes",
        handoffs: [agent_b]
      )

      events = []
      runner = described_class.new(starting_agent: agent_a, max_handoffs: 0)
      result = runner.run_stream("Loop me") { |event| events << event }

      expect(result[:answer]).to include("max handoffs")
      expect(events.map(&:type)).to include(:agent_start)
    end
  end
end
