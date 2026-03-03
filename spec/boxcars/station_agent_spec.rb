# frozen_string_literal: true

require "spec_helper"

RSpec.describe Boxcars::StationAgent do
  let(:calculator_boxcar_class) do
    Class.new(Boxcars::Boxcar) do
      def initialize(**kwargs)
        super(
          name: "Calculator",
          description: "Performs math",
          parameters: {
            question: { type: :string, required: true, description: "Math expression" }
          },
          **kwargs
        )
      end

      def call(inputs:)
        answer = case inputs[:question]
                 when "2+2" then "4"
                 else "unknown"
                 end
        { answer: Boxcars::Result.from_text(answer) }
      end
    end
  end

  let(:calculator_boxcar) { calculator_boxcar_class.new }

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

  let(:unsupported_engine_class) do
    Class.new(Boxcars::Engine) do
      def initialize
        super(description: "unsupported")
      end

      def run(_question)
        "nope"
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

  describe "construction" do
    it "creates with instructions and tools" do
      engine = fake_tool_engine_class.new(responses: [])
      agent = described_class.new(
        instructions: "You are a math helper.",
        tools: [calculator_boxcar],
        engine: engine
      )
      expect(agent.instructions).to eq("You are a math helper.")
      expect(agent.boxcars).to eq([calculator_boxcar])
      expect(agent.name).to eq("Station Agent")
      expect(agent.description).to eq("A helpful AI agent")
    end

    it "resolves engine from model: string" do
      allow(Boxcars::Engines).to receive(:engine).with(model: "sonnet").and_call_original
      # We just verify it delegates to Engines.engine; the actual engine creation may
      # fail without API keys, so we stub.
      fake_engine = fake_tool_engine_class.new(responses: [])
      allow(Boxcars::Engines).to receive(:engine).with(model: "sonnet").and_return(fake_engine)

      agent = described_class.new(instructions: "Hello", model: "sonnet")
      expect(agent.engine).to eq(fake_engine)
      expect(Boxcars::Engines).to have_received(:engine).with(model: "sonnet")
    end

    it "uses engine: directly when provided" do
      engine = fake_tool_engine_class.new(responses: [])
      agent = described_class.new(instructions: "Hello", engine: engine)
      expect(agent.engine).to eq(engine)
    end

    it "falls back to default engine when neither model nor engine given" do
      agent = described_class.new(instructions: "Hello")
      expect(agent.engine).to be_a(Boxcars::Engine)
    end

    it "forwards kwargs like max_iterations" do
      engine = fake_tool_engine_class.new(responses: [])
      agent = described_class.new(instructions: "Hello", engine: engine, max_iterations: 5)
      expect(agent.max_iterations).to eq(5)
    end

    it "accepts a custom name and description" do
      engine = fake_tool_engine_class.new(responses: [])
      agent = described_class.new(
        instructions: "Hello",
        engine: engine,
        name: "Research Bot",
        description: "Researches topics"
      )
      expect(agent.name).to eq("Research Bot")
      expect(agent.description).to eq("Researches topics")
    end
  end

  describe "instructions as system prompt" do
    it "system message in engine call contains the instructions text" do
      engine = fake_tool_engine_class.new(
        responses: [final_answer_response("The answer is 4.")]
      )

      agent = described_class.new(
        instructions: "You are a helpful math tutor. Always show your work.",
        tools: [calculator_boxcar],
        engine: engine
      )
      agent.run("What is 2+2?")

      first_call = engine.calls.first
      messages = first_call[:prompt].as_messages[:messages]
      system_msg = messages.find { |m| m[:role] == :system }
      expect(system_msg[:content]).to eq("You are a helpful math tutor. Always show your work.")
    end

    it "does not include boxcar_descriptions placeholder in prompt" do
      engine = fake_tool_engine_class.new(responses: [])
      agent = described_class.new(instructions: "Hello", engine: engine)
      prompt_text = agent.prompt.to_s
      expect(prompt_text).not_to include("boxcar_descriptions")
      expect(prompt_text).not_to include("next_actions")
    end
  end

  describe "agent-as-tool (nesting)" do
    it "tool_spec has single input string parameter" do
      engine = fake_tool_engine_class.new(responses: [])
      agent = described_class.new(instructions: "Hello", engine: engine)
      spec = agent.tool_spec

      expect(spec[:type]).to eq("function")
      expect(spec[:function][:parameters]).to eq(
        "type" => "object",
        "properties" => {
          "input" => {
            "type" => "string",
            "description" => "The task or question for this agent"
          }
        },
        "required" => ["input"],
        "additionalProperties" => false
      )
    end

    it "tool_call_name is sanitized from name" do
      engine = fake_tool_engine_class.new(responses: [])
      agent = described_class.new(instructions: "Hello", engine: engine, name: "Research Bot")
      expect(agent.tool_call_name).to eq("Research_Bot")
    end

    it "description (not instructions) is used in tool_spec" do
      engine = fake_tool_engine_class.new(responses: [])
      agent = described_class.new(
        instructions: "You are a secret internal prompt.",
        description: "A research assistant",
        engine: engine
      )
      spec = agent.tool_spec
      expect(spec[:function][:description]).to eq("A research assistant")
      expect(spec[:function][:description]).not_to include("secret internal prompt")
    end

    it "inner agent runs when outer agent calls it as a tool" do
      inner_engine = fake_tool_engine_class.new(
        responses: [final_answer_response("The capital of France is Paris.")]
      )
      inner_agent = described_class.new(
        instructions: "You are a geography expert.",
        engine: inner_engine,
        name: "Geography Agent",
        description: "Answers geography questions"
      )

      inner_tool_name = inner_agent.tool_call_name

      outer_engine = fake_tool_engine_class.new(
        responses: [
          tool_call_response("call_1", inner_tool_name, '{"input":"What is the capital of France?"}'),
          final_answer_response("According to my research, Paris is the capital of France.")
        ]
      )

      outer_agent = described_class.new(
        instructions: "You are a helpful assistant. Use your tools.",
        tools: [inner_agent],
        engine: outer_engine
      )

      result = outer_agent.run("What is the capital of France?")
      expect(result).to eq("According to my research, Paris is the capital of France.")
      expect(inner_engine.calls.length).to eq(1)
      expect(outer_engine.calls.length).to eq(2)
    end
  end

  describe "MCP integration" do
    it "discovers tools from MCP clients" do
      engine = fake_tool_engine_class.new(responses: [])
      fake_mcp_boxcar = calculator_boxcar_class.new

      fake_client = double("mcp_client") # rubocop:disable RSpec/VerifiedDoubles
      allow(Boxcars::MCP).to receive(:boxcars_from_client).with(fake_client).and_return([fake_mcp_boxcar])

      agent = described_class.new(
        instructions: "Hello",
        engine: engine,
        mcp_clients: [fake_client]
      )
      expect(agent.boxcars).to include(fake_mcp_boxcar)
    end

    it "combines local tools and MCP tools" do
      engine = fake_tool_engine_class.new(responses: [])
      mcp_boxcar = calculator_boxcar_class.new

      fake_client = double("mcp_client") # rubocop:disable RSpec/VerifiedDoubles
      allow(Boxcars::MCP).to receive(:boxcars_from_client).with(fake_client).and_return([mcp_boxcar])

      agent = described_class.new(
        instructions: "Hello",
        tools: [calculator_boxcar],
        engine: engine,
        mcp_clients: [fake_client]
      )
      expect(agent.boxcars).to eq([calculator_boxcar, mcp_boxcar])
    end
  end

  describe "lifecycle callbacks" do
    it "on_tool_call is called before execution with tool_name and args" do
      calls_log = []
      engine = fake_tool_engine_class.new(
        responses: [
          tool_call_response("call_1", "Calculator", '{"question":"2+2"}'),
          final_answer_response("The answer is 4.")
        ]
      )

      agent = described_class.new(
        instructions: "You are a math helper.",
        tools: [calculator_boxcar],
        engine: engine,
        on_tool_call: ->(tool_name, args) { calls_log << { tool_name: tool_name, args: args } }
      )
      agent.run("What is 2+2?")

      expect(calls_log.length).to eq(1)
      expect(calls_log.first[:tool_name]).to eq("Calculator")
      expect(calls_log.first[:args]).to eq({ question: "2+2" })
    end

    it "on_tool_call returning false blocks tool execution" do
      engine = fake_tool_engine_class.new(
        responses: [
          tool_call_response("call_1", "Calculator", '{"question":"2+2"}'),
          final_answer_response("I was blocked from using the calculator.")
        ]
      )

      agent = described_class.new(
        instructions: "You are a math helper.",
        tools: [calculator_boxcar],
        engine: engine,
        on_tool_call: ->(_tool_name, _args) { false }
      )
      result = agent.run("What is 2+2?")

      expect(result).to eq("I was blocked from using the calculator.")
      # Engine was called twice (initial + after blocked tool response), but calculator never ran
    end

    it "on_tool_call returning truthy allows normal execution" do
      calls_log = []
      engine = fake_tool_engine_class.new(
        responses: [
          tool_call_response("call_1", "Calculator", '{"question":"2+2"}'),
          final_answer_response("4")
        ]
      )

      agent = described_class.new(
        instructions: "You are a math helper.",
        tools: [calculator_boxcar],
        engine: engine,
        on_tool_call: lambda { |tool_name, _args|
          calls_log << tool_name
          true
        }
      )
      result = agent.run("What is 2+2?")

      expect(calls_log).to eq(["Calculator"])
      expect(result).to eq("4")
    end

    it "on_tool_result is called after execution with tool_name, args, and observation" do
      results_log = []
      engine = fake_tool_engine_class.new(
        responses: [
          tool_call_response("call_1", "Calculator", '{"question":"2+2"}'),
          final_answer_response("4")
        ]
      )

      agent = described_class.new(
        instructions: "You are a math helper.",
        tools: [calculator_boxcar],
        engine: engine,
        on_tool_result: lambda { |tool_name, args, observation|
          results_log << { tool_name: tool_name, args: args, observation: observation }
        }
      )
      agent.run("What is 2+2?")

      expect(results_log.length).to eq(1)
      expect(results_log.first[:tool_name]).to eq("Calculator")
      expect(results_log.first[:args]).to eq({ question: "2+2" })
      expect(results_log.first[:observation]).to be_a(Boxcars::Observation)
    end

    it "on_complete is called on finish without handoff" do
      complete_log = []
      engine = fake_tool_engine_class.new(
        responses: [final_answer_response("Hello!")]
      )

      agent = described_class.new(
        instructions: "Greet the user.",
        engine: engine,
        on_complete: ->(result) { complete_log << result }
      )
      agent.run("Hi!")

      expect(complete_log.length).to eq(1)
      expect(complete_log.first).to be_a(Hash)
    end

    it "on_complete is NOT called when handoff occurs" do
      complete_called = false
      target_engine = fake_tool_engine_class.new(responses: [])
      target_agent = described_class.new(
        instructions: "Target agent",
        engine: target_engine,
        name: "Target",
        description: "Handles things"
      )

      engine = fake_tool_engine_class.new(
        responses: [
          tool_call_response("call_1", "handoff_to_target", '{"reason":"needs specialized help"}')
        ]
      )

      agent = described_class.new(
        instructions: "Route to the right agent.",
        engine: engine,
        handoffs: [target_agent],
        on_complete: ->(_result) { complete_called = true }
      )
      agent.conduct("Help me")

      expect(complete_called).to be false
    end
  end

  describe "handoffs" do
    let(:target_engine) { fake_tool_engine_class.new(responses: []) }
    let(:target_agent) do
      described_class.new(
        instructions: "Target agent",
        engine: target_engine,
        name: "Billing Agent",
        description: "Handles billing questions"
      )
    end

    it "handoff agents appear as tools with handoff_to_ prefix" do
      engine = fake_tool_engine_class.new(responses: [])
      agent = described_class.new(
        instructions: "Route requests.",
        engine: engine,
        handoffs: [target_agent]
      )

      handoff_boxcar = agent.boxcars.find { |b| b.is_a?(Boxcars::StationAgent::HandoffBoxcar) }
      expect(handoff_boxcar).not_to be_nil
      expect(handoff_boxcar.name).to eq("handoff_to_billing_agent")
    end

    it "HandoffBoxcar has return_direct: true" do
      engine = fake_tool_engine_class.new(responses: [])
      agent = described_class.new(
        instructions: "Route requests.",
        engine: engine,
        handoffs: [target_agent]
      )

      handoff_boxcar = agent.boxcars.find { |b| b.is_a?(Boxcars::StationAgent::HandoffBoxcar) }
      expect(handoff_boxcar.return_direct).to be true
    end

    it ":handoff is set in result when handoff tool is called" do
      engine = fake_tool_engine_class.new(
        responses: [
          tool_call_response("call_1", "handoff_to_billing_agent", '{"reason":"billing question"}')
        ]
      )

      agent = described_class.new(
        instructions: "Route requests.",
        engine: engine,
        handoffs: [target_agent]
      )

      result = agent.conduct("How much do I owe?")
      handoff = result.respond_to?(:output_for) ? result.output_for(:handoff) : result[:handoff]
      expect(handoff).not_to be_nil
      expect(handoff[:agent]).to eq(target_agent)
      expect(handoff[:reason]).to eq("billing question")
    end

    it ":handoff is not set when no handoff occurs" do
      engine = fake_tool_engine_class.new(
        responses: [final_answer_response("Just a regular answer.")]
      )

      agent = described_class.new(
        instructions: "Route requests.",
        engine: engine,
        handoffs: [target_agent]
      )

      result = agent.conduct("Hello")
      handoff = result.respond_to?(:output_for) ? result.output_for(:handoff) : result[:handoff]
      expect(handoff).to be_nil
    end

    it "output_keys includes :handoff" do
      engine = fake_tool_engine_class.new(responses: [])
      agent = described_class.new(
        instructions: "Route requests.",
        engine: engine,
        handoffs: [target_agent]
      )

      expect(agent.output_keys).to include(:handoff)
    end
  end

  describe "event streaming" do
    it "direct answer emits agent_start, llm_call_start, llm_response, agent_complete" do
      events = []
      engine = fake_tool_engine_class.new(responses: [final_answer_response("Hello!")])

      agent = described_class.new(
        instructions: "Greet the user.",
        engine: engine,
        on_event: ->(event) { events << event }
      )
      agent.run("Hi!")

      types = events.map(&:type)
      expect(types).to eq(%i[agent_start llm_call_start llm_response agent_complete])
    end

    it "tool-calling flow emits tool events between LLM events" do
      events = []
      engine = fake_tool_engine_class.new(
        responses: [
          tool_call_response("call_1", "Calculator", '{"question":"2+2"}'),
          final_answer_response("4")
        ]
      )

      agent = described_class.new(
        instructions: "Math helper.",
        tools: [calculator_boxcar],
        engine: engine,
        on_event: ->(event) { events << event }
      )
      agent.run("What is 2+2?")

      types = events.map(&:type)
      expect(types).to eq(
        %i[
          agent_start
          llm_call_start llm_response
          tool_call_start tool_call_end
          llm_call_start llm_response
          agent_complete
        ]
      )
    end

    it "blocked tool emits tool_call_blocked" do
      events = []
      engine = fake_tool_engine_class.new(
        responses: [
          tool_call_response("call_1", "Calculator", '{"question":"2+2"}'),
          final_answer_response("Blocked.")
        ]
      )

      agent = described_class.new(
        instructions: "Math helper.",
        tools: [calculator_boxcar],
        engine: engine,
        on_tool_call: ->(_name, _args) { false },
        on_event: ->(event) { events << event }
      )
      agent.run("What is 2+2?")

      types = events.map(&:type)
      expect(types).to include(:tool_call_blocked)
      expect(types).not_to include(:tool_call_start)
    end

    it "handoff emits handoff event" do
      events = []
      target_engine = fake_tool_engine_class.new(responses: [])
      target_agent = described_class.new(
        instructions: "Target", engine: target_engine, name: "Target", description: "Handles things"
      )

      engine = fake_tool_engine_class.new(
        responses: [
          tool_call_response("call_1", "handoff_to_target", '{"reason":"needs help"}')
        ]
      )

      agent = described_class.new(
        instructions: "Route.", engine: engine, handoffs: [target_agent],
        on_event: ->(event) { events << event }
      )
      agent.conduct("Help")

      types = events.map(&:type)
      expect(types).to include(:handoff)
      handoff_event = events.find { |e| e.type == :handoff }
      expect(handoff_event.data[:to_agent]).to eq("Target")
    end

    it "callback errors do not break agent loop" do
      engine = fake_tool_engine_class.new(responses: [final_answer_response("Hello!")])

      agent = described_class.new(
        instructions: "Greet.",
        engine: engine,
        on_event: ->(_event) { raise "boom" }
      )

      expect { agent.run("Hi!") }.not_to raise_error
    end

    it "tool_call_end includes duration_ms and status" do
      events = []
      engine = fake_tool_engine_class.new(
        responses: [
          tool_call_response("call_1", "Calculator", '{"question":"2+2"}'),
          final_answer_response("4")
        ]
      )

      agent = described_class.new(
        instructions: "Math helper.",
        tools: [calculator_boxcar],
        engine: engine,
        on_event: ->(event) { events << event }
      )
      agent.run("What is 2+2?")

      tool_end = events.find { |e| e.type == :tool_call_end }
      expect(tool_end.data[:duration_ms]).to be_a(Integer)
      expect(tool_end.data[:duration_ms]).to be >= 0
      expect(tool_end.data[:status]).to eq(:success)
    end

    it "agent_complete includes iterations and tool_calls_count" do
      events = []
      engine = fake_tool_engine_class.new(
        responses: [
          tool_call_response("call_1", "Calculator", '{"question":"2+2"}'),
          final_answer_response("4")
        ]
      )

      agent = described_class.new(
        instructions: "Math helper.",
        tools: [calculator_boxcar],
        engine: engine,
        on_event: ->(event) { events << event }
      )
      agent.run("What is 2+2?")

      complete = events.find { |e| e.type == :agent_complete }
      expect(complete.data[:iterations]).to eq(2)
      expect(complete.data[:tool_calls_count]).to eq(1)
    end
  end

  describe "#run_stream" do
    it "with block yields events and returns ConductResult" do
      events = []
      engine = fake_tool_engine_class.new(responses: [final_answer_response("Hello!")])

      agent = described_class.new(instructions: "Greet.", engine: engine)
      result = agent.run_stream("Hi!") { |event| events << event }

      types = events.map(&:type)
      expect(types).to eq(%i[agent_start llm_call_start llm_response agent_complete])
      expect(result).to be_a(Boxcars::ConductResult)
    end

    it "without block returns Enumerator" do
      engine = fake_tool_engine_class.new(responses: [final_answer_response("Hello!")])
      agent = described_class.new(instructions: "Greet.", engine: engine)

      stream = agent.run_stream("Hi!")
      expect(stream).to be_a(Enumerator)

      events = stream.to_a
      types = events.map(&:type)
      expect(types).to eq(%i[agent_start llm_call_start llm_response agent_complete])
    end

    it "restores original on_event after execution" do
      original_events = []
      original_handler = ->(event) { original_events << event }
      engine = fake_tool_engine_class.new(
        responses: [
          final_answer_response("First."),
          final_answer_response("Second.")
        ]
      )

      agent = described_class.new(instructions: "Greet.", engine: engine, on_event: original_handler)

      stream_events = []
      agent.run_stream("Hi!") { |event| stream_events << event }
      expect(agent.on_event).to eq(original_handler)

      # Run again normally — events should go to the original handler
      agent.run("Hi again!")
      expect(original_events.map(&:type)).to include(:agent_start)
    end
  end

  describe "edge cases" do
    it "works with zero tools (direct answer mode)" do
      engine = fake_tool_engine_class.new(
        responses: [final_answer_response("Hello! How can I help you?")]
      )

      agent = described_class.new(instructions: "You are friendly.", engine: engine)
      result = agent.run("Hi there!")
      expect(result).to eq("Hello! How can I help you?")
    end

    it "raises on non-tool-calling engine" do
      agent = described_class.new(instructions: "Hello", engine: unsupported_engine_class.new)
      expect { agent.run("test") }
        .to raise_error(Boxcars::ArgumentError, /does not support native tool-calling/)
    end

    it "custom name affects tool_call_name" do
      engine = fake_tool_engine_class.new(responses: [])
      agent = described_class.new(instructions: "Hello", engine: engine, name: "My Custom Agent!")
      expect(agent.tool_call_name).to eq("My_Custom_Agent")
    end

    it "input_keys returns [:input]" do
      engine = fake_tool_engine_class.new(responses: [])
      agent = described_class.new(instructions: "Hello", engine: engine)
      expect(agent.input_keys).to eq([:input])
    end
  end
end
