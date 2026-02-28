# frozen_string_literal: true

require "spec_helper"

RSpec.describe Boxcars::MCP do
  let(:fake_mcp_client_class) do
    Class.new(Boxcars::MCP::Client) do
      def initialize(name:)
        @name = name
      end

      def list_tools
        [
          {
            "name" => "#{@name}_tool",
            "description" => "Tool for #{@name}",
            "inputSchema" => {
              "type" => "object",
              "properties" => {
                "q" => { "type" => "string" }
              },
              "required" => ["q"],
              "additionalProperties" => false
            }
          }
        ]
      end

      def call_tool(name:, arguments:)
        { "structuredContent" => { "name" => name, "arguments" => arguments } }
      end
    end
  end

  let(:fake_tool_engine_class) do
    Class.new(Boxcars::Engine) do
      def initialize
        super(description: "fake")
      end

      def capabilities
        super.merge(tool_calling: true)
      end

      def client(*, **)
        raise "not used in this spec"
      end

      def run(_question)
        raise NotImplementedError
      end
    end
  end

  let(:local_boxcar_class) do
    Class.new(Boxcars::Boxcar) do
      def initialize
        super(name: "LocalTool", description: "local", parameters: { question: { type: :string, required: true } })
      end

      def call(inputs:)
        { answer: Boxcars::Result.from_text(inputs[:question].to_s) }
      end

      def apply(input_list:)
        input_list
      end
    end
  end

  it "builds a ToolTrain from local Boxcars and MCP clients" do
    client_a = fake_mcp_client_class.new(name: "alpha")
    client_b = fake_mcp_client_class.new(name: "beta")
    engine = fake_tool_engine_class.new
    local_boxcar = local_boxcar_class.new

    train = described_class.tool_train(
      engine: engine,
      boxcars: [local_boxcar],
      clients: [client_a, client_b],
      client_name_prefixes: { 0 => "Docs", 1 => "Files" }
    )

    expect(train).to be_a(Boxcars::ToolTrain)
    expect(train.boxcars.map(&:name)).to eq(["LocalTool", "Docs: alpha_tool", "Files: beta_tool"])
    expect(train.boxcars[1]).to be_a(Boxcars::MCP::ToolBoxcar)
    expect(train.boxcars[2]).to be_a(Boxcars::MCP::ToolBoxcar)
  end

  it "uses default MCP prefixes when none are provided" do
    client = fake_mcp_client_class.new(name: "alpha")
    engine = fake_tool_engine_class.new

    train = described_class.tool_train(engine:, clients: [client])

    expect(train.boxcars.map(&:name)).to eq(["MCP1: alpha_tool"])
  end

  it "keeps tool_calling_train as a compatibility alias" do
    client = fake_mcp_client_class.new(name: "alpha")
    engine = fake_tool_engine_class.new

    train = described_class.tool_calling_train(engine:, clients: [client])

    expect(train).to be_a(Boxcars::ToolTrain)
  end
end
