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

  describe "#run contract" do
    let(:result_boxcar_class) do
      Class.new(described_class) do
        def call(inputs:)
          { answer: Boxcars::Result.new(status: :ok, answer: "echo: #{inputs[:question]}", explanation: "ok") }
        end

        def apply(input_list:)
          input_list.map { |inputs| call(inputs:) }
        end
      end
    end

    let(:custom_output_boxcar_class) do
      Class.new(described_class) do
        def output_keys
          [:foo]
        end

        def call(inputs:)
          { foo: "value: #{inputs[:question]}" }
        end

        def apply(input_list:)
          input_list.map { |inputs| call(inputs:) }
        end
      end
    end

    let(:invalid_output_boxcar_class) do
      Class.new(described_class) do
        def call(inputs:)
          "not-a-hash: #{inputs[:question]}"
        end

        def apply(input_list:)
          input_list
        end
      end
    end

    it "unwraps Boxcars::Result to the contained answer value" do
      boxcar = result_boxcar_class.new(description: "Result wrapper")
      expect(boxcar.run("hello")).to eq("echo: hello")
    end

    it "returns the first configured output key value for non-standard output keys" do
      boxcar = custom_output_boxcar_class.new(description: "Custom output")
      expect(boxcar.run("hello")).to eq("value: hello")
    end

    it "raises a clear error when #call does not return a hash" do
      boxcar = invalid_output_boxcar_class.new(description: "Invalid output")

      expect do
        boxcar.run("hello")
      end.to raise_error(Boxcars::Error, /#call must return a Hash/)
    end

    it "returns a ConductResult from #conduct" do
      boxcar = result_boxcar_class.new(description: "Result wrapper")
      expect(boxcar.conduct("hello")).to be_a(Boxcars::ConductResult)
    end

    it "supports legacy result[:answer].answer with a deprecation warning" do
      Boxcars::ConductResult.reset_deprecation_warnings!
      allow(Boxcars).to receive(:warn)

      boxcar = result_boxcar_class.new(description: "Result wrapper")
      result = boxcar.conduct("hello")

      expect(result[:answer].answer).to eq("echo: hello")
      expect(Boxcars).to have_received(:warn).once
    end
  end
end
