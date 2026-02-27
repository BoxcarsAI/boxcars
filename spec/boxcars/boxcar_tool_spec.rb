# frozen_string_literal: true

require "spec_helper"

RSpec.describe Boxcars::Boxcar do
  let(:boxcar_class) do
    Class.new(described_class) do
      def call(inputs:)
        { answer: inputs.inspect }
      end

      def apply(input_list:)
        input_list
      end
    end
  end

  describe "#tool_call_name" do
    it "sanitizes names for provider tool-calling constraints" do
      boxcar = boxcar_class.new(
        name: "Weather Search API v1!",
        description: "Weather lookup"
      )

      expect(boxcar.tool_call_name).to eq("Weather_Search_API_v1")
    end

    it "prefixes names that do not start with a letter or underscore" do
      boxcar = boxcar_class.new(
        name: "123 tool",
        description: "Numeric name"
      )

      expect(boxcar.tool_call_name).to eq("boxcar_123_tool")
    end
  end

  describe "#parameters_json_schema" do
    it "converts legacy parameter descriptors into JSON Schema" do
      boxcar = boxcar_class.new(
        name: "Weather Search API",
        description: "Weather lookup",
        parameters: {
          city: { type: :string, description: "City name", required: true },
          days: { type: :int, description: "Forecast days" },
          include_hourly: { type: :bool, description: "Include hourly data" }
        }
      )

      expect(boxcar.parameters_json_schema).to eq(
        {
          "type" => "object",
          "properties" => {
            "city" => { "type" => "string", "description" => "City name" },
            "days" => { "type" => "integer", "description" => "Forecast days" },
            "include_hourly" => { "type" => "boolean", "description" => "Include hourly data" }
          },
          "required" => ["city"],
          "additionalProperties" => false
        }
      )
    end

    it "accepts nested JSON schema fragments via json_schema" do
      boxcar = boxcar_class.new(
        name: "Search",
        description: "Search docs",
        parameters: {
          filters: {
            required: true,
            json_schema: {
              type: :object,
              properties: {
                tags: { type: :array, items: { type: :string } },
                range: {
                  type: :object,
                  properties: {
                    min: { type: :number },
                    max: { type: :number }
                  },
                  required: %i[min max]
                }
              },
              required: [:tags],
              additional_properties: false
            }
          }
        }
      )

      expect(boxcar.parameters_json_schema).to eq(
        {
          "type" => "object",
          "properties" => {
            "filters" => {
              "type" => "object",
              "properties" => {
                "tags" => { "type" => "array", "items" => { "type" => "string" } },
                "range" => {
                  "type" => "object",
                  "properties" => {
                    "min" => { "type" => "number" },
                    "max" => { "type" => "number" }
                  },
                  "required" => %w[min max]
                }
              },
              "required" => ["tags"],
              "additionalProperties" => false
            }
          },
          "required" => ["filters"],
          "additionalProperties" => false
        }
      )
    end
  end

  describe "#tool_spec" do
    it "returns an OpenAI-compatible function tool definition" do
      boxcar = boxcar_class.new(
        name: "Weather Search API",
        description: "Weather lookup",
        parameters: { city: { type: :string, required: true, description: "City" } }
      )

      expect(boxcar.tool_spec).to eq(
        {
          type: "function",
          function: {
            name: "Weather_Search_API",
            description: "Weather lookup",
            parameters: {
              "type" => "object",
              "properties" => {
                "city" => { "type" => "string", "description" => "City" }
              },
              "required" => ["city"],
              "additionalProperties" => false
            }
          }
        }
      )
    end
  end
end
