# frozen_string_literal: true

require "spec_helper"
require "rbconfig"
require "tempfile"

RSpec.describe Boxcars::MCP::StdioClient do
  def build_fake_mcp_server_script
    Tempfile.new(["fake_mcp_server", ".rb"]).tap do |file|
      file.write(<<~RUBY)
        # frozen_string_literal: true
        require "json"

        def read_message(io)
          headers = {}
          loop do
            line = io.gets
            exit 0 if line.nil?
            line = line.strip
            break if line.empty?
            key, value = line.split(":", 2)
            headers[key.downcase] = value.strip if key && value
          end
          len = Integer(headers.fetch("content-length"))
          body = io.read(len)
          JSON.parse(body)
        end

        def write_message(io, payload)
          json = JSON.generate(payload)
          io.write("Content-Length: \#{json.bytesize}\\r\\n\\r\\n")
          io.write(json)
          io.flush
        end

        loop do
          msg = read_message($stdin)
          method = msg["method"]
          case method
          when "initialize"
            write_message($stdout, {
              jsonrpc: "2.0",
              id: msg["id"],
              result: {
                protocolVersion: msg.dig("params", "protocolVersion"),
                capabilities: { tools: {} },
                serverInfo: { name: "fake-mcp", version: "0.1.0" }
              }
            })
          when "notifications/initialized"
            # no-op notification
          when "tools/list"
            write_message($stdout, {
              jsonrpc: "2.0",
              id: msg["id"],
              result: {
                tools: [
                  {
                    name: "echo_tool",
                    description: "Echoes input",
                    inputSchema: {
                      type: "object",
                      properties: { text: { type: "string" } },
                      required: ["text"],
                      additionalProperties: false
                    }
                  }
                ]
              }
            })
          when "tools/call"
            text = msg.dig("params", "arguments", "text")
            write_message($stdout, {
              jsonrpc: "2.0",
              id: msg["id"],
              result: {
                structuredContent: { echoed: text },
                content: [{ type: "text", text: "ok" }]
              }
            })
          else
            write_message($stdout, {
              jsonrpc: "2.0",
              id: msg["id"],
              error: { code: -32601, message: "Method not found: \#{method}" }
            })
          end
        end
      RUBY
      file.flush
    end
  end

  it "initializes over stdio and supports tools/list + tools/call" do
    script = build_fake_mcp_server_script
    client = described_class.new(
      command: RbConfig.ruby,
      args: [script.path],
      initialization_timeout: 3
    )

    begin
      client.connect!
      expect(client.server_info).to eq("name" => "fake-mcp", "version" => "0.1.0")
      expect(client.server_capabilities).to eq("tools" => {})

      tools = client.list_tools
      expect(tools.length).to eq(1)
      expect(tools.first["name"]).to eq("echo_tool")

      result = client.call_tool(name: "echo_tool", arguments: { "text" => "hello" })
      expect(result).to eq(
        "structuredContent" => { "echoed" => "hello" },
        "content" => [{ "type" => "text", "text" => "ok" }]
      )
    ensure
      client.close
      script.close!
    end
  end

  it "provides a convenience constructor via Boxcars::MCP.stdio" do
    script = build_fake_mcp_server_script
    client = nil

    begin
      client = Boxcars::MCP.stdio(command: RbConfig.ruby, args: [script.path], initialization_timeout: 3)
      expect(client).to be_a(described_class)
      expect(client.server_info).to eq("name" => "fake-mcp", "version" => "0.1.0")
    ensure
      client&.close
      script.close!
    end
  end
end
