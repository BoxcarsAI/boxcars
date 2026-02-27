# frozen_string_literal: true

module Boxcars
  module MCP
    # Abstract MCP client interface. Concrete implementations can use stdio,
    # HTTP, SSE, or in-process transports.
    class Client
      # @return [Array<Hash>] MCP tool descriptors (at minimum name, description, inputSchema)
      def list_tools
        raise NotImplementedError
      end

      # @param name [String] MCP tool name
      # @param arguments [Hash] JSON-compatible arguments for the tool
      # @return [Hash] MCP tool result payload
      def call_tool(name:, arguments:)
        raise NotImplementedError
      end
    end
  end
end
