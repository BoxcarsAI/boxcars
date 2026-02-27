# frozen_string_literal: true

module Boxcars
  # Model Context Protocol integration namespace.
  module MCP
    def self.boxcars_from_client(client, **kwargs)
      ToolRegistry.boxcars_from_client(client, **kwargs)
    end

    def self.stdio(command:, args: [], **kwargs)
      StdioClient.new(command:, args:, **kwargs).connect!
    end

    # Build a ToolCallingTrain from local Boxcars plus tools discovered from
    # one or more MCP clients.
    #
    # @param engine [Boxcars::Engine] Tool-calling capable engine (required)
    # @param boxcars [Array<Boxcars::Boxcar>] Local Boxcars to include
    # @param clients [Array<Boxcars::MCP::Client>] MCP clients to discover tools from
    # @param client_name_prefixes [Hash,Integer=>String] Optional prefixes by client index or object_id
    # @param mcp_return_direct [Boolean] Whether discovered MCP boxcars return direct
    # @param train_kwargs [Hash] Additional args for Boxcars::ToolCallingTrain
    def self.tool_calling_train(engine:, boxcars: [], clients: [], client_name_prefixes: {}, mcp_return_direct: false, **train_kwargs)
      unless defined?(Boxcars::ToolCallingTrain)
        raise Boxcars::Error, "Boxcars::ToolCallingTrain is not loaded. Require 'boxcars' before using MCP helpers."
      end

      combined_boxcars = Array(boxcars).dup
      Array(clients).each_with_index do |client, index|
        prefix = mcp_client_prefix(client, index, client_name_prefixes)
        combined_boxcars.concat(
          boxcars_from_client(client, name_prefix: prefix, return_direct: mcp_return_direct)
        )
      end

      Boxcars::ToolCallingTrain.new(boxcars: combined_boxcars, engine:, **train_kwargs)
    end

    def self.mcp_client_prefix(client, index, client_name_prefixes)
      client_name_prefixes[index] ||
        client_name_prefixes[client.object_id] ||
        client_name_prefixes[client] ||
        (Array(client_name_prefixes.values_at(:default, "default")).compact.first) ||
        "MCP#{index + 1}"
    end
    private_class_method :mcp_client_prefix
  end
end

require "boxcars/mcp/client"
require "boxcars/mcp/stdio_client"
require "boxcars/mcp/tool_boxcar"
require "boxcars/mcp/tool_registry"
