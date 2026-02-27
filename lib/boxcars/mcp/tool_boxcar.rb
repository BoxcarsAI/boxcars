# frozen_string_literal: true

require "json"

module Boxcars
  module MCP
    # Wraps an MCP tool as a standard Boxcar so it can be used in Trains.
    class ToolBoxcar < Boxcar
      attr_reader :mcp_client, :tool_name, :tool_description, :input_schema

      def initialize(mcp_client:, tool_name:, tool_description: nil, input_schema: {}, name_prefix: nil, **kwargs)
        @mcp_client = mcp_client
        @tool_name = tool_name.to_s
        @tool_description = tool_description.to_s.strip
        @tool_description = "MCP tool #{@tool_name}" if @tool_description.empty?
        @input_schema = deep_stringify(input_schema || {})

        kwargs[:name] ||= [name_prefix, @tool_name].compact.join(": ")
        kwargs[:description] ||= @tool_description
        kwargs[:parameters] ||= mcp_schema_to_parameters(@input_schema)
        super(**kwargs)
      end

      def call(inputs:)
        payload = mcp_client.call_tool(name: tool_name, arguments: stringify_keys(inputs))
        result = mcp_payload_to_result(payload)
        { answer: result }
      end

      def input_keys
        parameters.keys
      end

      def apply(input_list:)
        input_list.map { |inputs| call(inputs:) }
      end

      # Prefer the MCP-provided schema over the legacy parameter map.
      def parameters_json_schema
        schema = deep_stringify(input_schema)
        return super if schema.empty?

        schema["type"] ||= "object"
        schema["properties"] ||= {}
        schema
      end

      private

      def mcp_schema_to_parameters(schema)
        properties = schema.is_a?(Hash) ? (schema["properties"] || schema[:properties] || {}) : {}
        required = schema.is_a?(Hash) ? (schema["required"] || schema[:required] || []) : []
        required_names = required.map(&:to_s)

        return {} if schema.is_a?(Hash) && schema["type"].to_s == "object" && properties.empty?
        return default_parameters if properties.empty?

        properties.each_with_object({}) do |(param_name, prop_schema), out|
          prop = deep_symbolize(prop_schema || {})
          out[param_name.to_sym] = {
            type: infer_legacy_type(prop[:type]),
            description: prop[:description] || "MCP tool parameter",
            required: required_names.include?(param_name.to_s),
            json_schema: deep_stringify(prop)
          }
        end
      end

      def default_parameters
        { question: { type: :string, description: "the input question", required: true } }
      end

      def infer_legacy_type(type)
        resolved = type.is_a?(Array) ? type.find { |t| t.to_s != "null" } : type
        case resolved.to_s
        when "integer" then :integer
        when "number" then :number
        when "boolean" then :boolean
        when "array" then :array
        when "object" then :object
        else :string
        end
      end

      def mcp_payload_to_result(payload)
        hash_payload = payload.is_a?(Hash) ? payload : { "content" => payload }
        is_error = hash_payload["isError"] || hash_payload[:isError] || hash_payload["is_error"] || hash_payload[:is_error]

        if (structured = hash_payload["structuredContent"] || hash_payload[:structuredContent] || hash_payload["structured_content"] || hash_payload[:structured_content])
          return is_error ? Result.from_error(stringify_for_error(structured)) : Result.new(status: :ok, answer: structured, explanation: structured)
        end

        if (content = hash_payload["content"] || hash_payload[:content])
          text = extract_mcp_content_text(content)
          return is_error ? Result.from_error(text) : Result.from_text(text)
        end

        text = hash_payload.to_s
        is_error ? Result.from_error(text) : Result.from_text(text)
      end

      def extract_mcp_content_text(content)
        case content
        when String
          content
        when Array
          texts = content.filter_map do |item|
            next unless item.is_a?(Hash)

            item_type = (item["type"] || item[:type]).to_s
            if item_type == "text"
              item["text"] || item[:text]
            elsif item.key?("text") || item.key?(:text)
              item["text"] || item[:text]
            elsif item_type == "json"
              JSON.generate(item["json"] || item[:json])
            end
          end
          texts.join("\n").strip
        when Hash
          text = content["text"] || content[:text]
          return text if text

          JSON.generate(content)
        else
          content.to_s
        end
      end

      def stringify_for_error(value)
        case value
        when String then value
        else JSON.generate(value)
        end
      rescue StandardError
        value.to_s
      end

      def stringify_keys(value)
        case value
        when Hash
          value.each_with_object({}) { |(k, v), out| out[k.to_s] = stringify_keys(v) }
        when Array
          value.map { |v| stringify_keys(v) }
        else
          value
        end
      end

      def deep_stringify(value)
        case value
        when Hash
          value.each_with_object({}) { |(k, v), out| out[k.to_s] = deep_stringify(v) }
        when Array
          value.map { |v| deep_stringify(v) }
        else
          value
        end
      end

      def deep_symbolize(value)
        case value
        when Hash
          value.each_with_object({}) { |(k, v), out| out[k.to_sym] = deep_symbolize(v) }
        when Array
          value.map { |v| deep_symbolize(v) }
        else
          value
        end
      rescue StandardError
        value
      end
    end
  end
end
