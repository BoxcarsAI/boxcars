# frozen_string_literal: true

require "spec_helper"

RSpec.describe Boxcars::MCP do
  let(:fake_client_class) do
    Class.new(Boxcars::MCP::Client) do
      attr_reader :calls

      def initialize
        @calls = []
      end

      def list_tools
        [
          {
            "name" => "weather_lookup",
            "description" => "Get weather",
            "inputSchema" => {
              "type" => "object",
              "properties" => {
                "city" => { "type" => "string", "description" => "City name" },
                "days" => { "type" => "integer" }
              },
              "required" => ["city"],
              "additionalProperties" => false
            }
          }
        ]
      end

      def call_tool(name:, arguments:)
        @calls << { name:, arguments: }
        case name
        when "weather_lookup"
          {
            "structuredContent" => {
              "city" => arguments["city"],
              "forecast" => "sunny"
            }
          }
        when "error_tool"
          {
            "isError" => true,
            "content" => [{ "type" => "text", "text" => "boom" }]
          }
        else
          { "content" => [{ "type" => "text", "text" => "ok" }] }
        end
      end
    end
  end

  let(:client) { fake_client_class.new }

  describe ".boxcars_from_client" do
    it "discovers MCP tools and wraps them as Boxcars" do
      boxcars = described_class.boxcars_from_client(client, name_prefix: "MCP")

      expect(boxcars.length).to eq(1)
      boxcar = boxcars.first
      expect(boxcar).to be_a(Boxcars::MCP::ToolBoxcar)
      expect(boxcar.name).to eq("MCP: weather_lookup")
      expect(boxcar.description).to eq("Get weather")
      expect(boxcar.tool_spec).to eq(
        {
          type: "function",
          function: {
            name: "MCP_weather_lookup",
            description: "Get weather",
            parameters: {
              "type" => "object",
              "properties" => {
                "city" => { "type" => "string", "description" => "City name" },
                "days" => { "type" => "integer" }
              },
              "required" => ["city"],
              "additionalProperties" => false
            }
          }
        }
      )
    end
  end

  describe Boxcars::MCP::ToolBoxcar do
    it "executes MCP tool calls and returns structured content" do
      boxcar = described_class.new(
        mcp_client: client,
        tool_name: "weather_lookup",
        tool_description: "Get weather",
        input_schema: client.list_tools.first["inputSchema"]
      )

      result = boxcar.run(city: "Austin", days: 2)

      expect(client.calls).to eq([{ name: "weather_lookup", arguments: { "city" => "Austin", "days" => 2 } }])
      expect(result).to eq({ "city" => "Austin", "forecast" => "sunny" })
    end

    it "converts MCP error payloads into error results" do
      boxcar = described_class.new(
        mcp_client: client,
        tool_name: "error_tool",
        tool_description: "Always fails",
        input_schema: { "type" => "object", "properties" => {}, "additionalProperties" => false }
      )

      result = boxcar.conduct({})
      answer = Boxcars::Result.extract(result)

      expect(answer).to be_a(Boxcars::Result)
      expect(answer.status).to eq(:error)
      expect(answer.answer).to eq("boom")
    end
  end
end
