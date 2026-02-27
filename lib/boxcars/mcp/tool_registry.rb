# frozen_string_literal: true

module Boxcars
  module MCP
    # Converts MCP tool descriptors into Boxcar wrappers.
    class ToolRegistry
      def self.boxcars_from_client(client, **kwargs)
        new(client:).boxcars(**kwargs)
      end

      attr_reader :client

      def initialize(client:)
        @client = client
      end

      def boxcars(name_prefix: nil, return_direct: false)
        client.list_tools.map do |tool|
          MCP::ToolBoxcar.new(
            mcp_client: client,
            tool_name: fetch_tool_field(tool, :name),
            tool_description: fetch_tool_field(tool, :description),
            input_schema: fetch_tool_field(tool, :inputSchema) || {},
            name_prefix: name_prefix,
            return_direct: return_direct
          )
        end
      end

      private

      def fetch_tool_field(tool, key)
        tool[key] || tool[key.to_s]
      end
    end
  end
end
