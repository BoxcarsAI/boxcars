# frozen_string_literal: true

require "spec_helper"

RSpec.describe Boxcars::JSONEngineBoxcar do
  let(:native_structured_engine_class) do
    Class.new(Boxcars::Engine) do
      attr_reader :calls

      def initialize
        @calls = []
        super(description: "native structured fake")
      end

      def capabilities
        super.merge(structured_output_json_schema: true, responses_api: false)
      end

      def client(prompt:, inputs: {}, **kwargs)
        @calls << { prompt:, inputs:, kwargs: }
        {
          "choices" => [
            {
              "message" => {
                "role" => "assistant",
                "content" => '{"share_count":"12,321,999"}'
              }
            }
          ]
        }
      end

      def run(_question)
        raise NotImplementedError
      end
    end
  end

  let(:responses_structured_engine_class) do
    Class.new(Boxcars::Engine) do
      attr_reader :calls

      def initialize
        @calls = []
        super(description: "responses structured fake")
      end

      def capabilities
        super.merge(structured_output_json_schema: true, responses_api: true)
      end

      def client(prompt:, inputs: {}, **kwargs)
        @calls << { prompt:, inputs:, kwargs: }
        { "output_text" => '{"share_count":"12,321,999"}' }
      end

      def run(_question)
        raise NotImplementedError
      end
    end
  end

  describe "#get_answer with json_schema" do
    let(:schema) do
      {
        type: "object",
        properties: {
          share_count: { type: "string" },
          confidence: { type: %w[number null] }
        },
        required: ["share_count"],
        additionalProperties: false
      }
    end

    it "accepts valid JSON matching the schema" do
      boxcar = described_class.new(json_schema: schema)

      result = boxcar.get_answer('{"share_count":"12,321,999","confidence":0.9}')

      expect(result.status).to eq(:ok)
      expect(result.answer).to eq({ "share_count" => "12,321,999", "confidence" => 0.9 })
    end

    it "returns an error result when parsed JSON violates the schema" do
      boxcar = described_class.new(json_schema: schema)

      result = boxcar.get_answer('{"share_count":123,"unexpected":"x"}')

      expect(result.status).to eq(:error)
      expect(result.answer).to match(/JSON schema validation error/)
      expect(result.answer).to match(/\$\.share_count: expected string/)
    end

    it "can allow schema violations when strict validation is disabled" do
      boxcar = described_class.new(json_schema: schema, json_schema_strict: false)

      result = boxcar.get_answer('{"share_count":123}')

      expect(result.status).to eq(:ok)
      expect(result.answer).to eq({ "share_count" => 123 })
    end
  end

  describe "native structured output generation" do
    it "passes response_format json_schema to capable engines" do
      schema = {
        type: "object",
        properties: { share_count: { type: "string" } },
        required: ["share_count"],
        additionalProperties: false
      }
      engine = native_structured_engine_class.new
      boxcar = described_class.new(engine:, json_schema: schema)

      result = boxcar.run("extract shares")

      expect(result).to eq({ "share_count" => "12,321,999" })
      expect(engine.calls.length).to eq(1)

      response_format = engine.calls.first[:kwargs][:response_format]
      expect(response_format).to eq(
        {
          type: "json_schema",
          json_schema: {
            name: "boxcars_json_output",
            strict: true,
            schema: {
              "type" => "object",
              "properties" => { "share_count" => { "type" => "string" } },
              "required" => ["share_count"],
              "additionalProperties" => false
            }
          }
        }
      )
    end

    it "also uses native response_format for responses-capable engines" do
      schema = {
        type: "object",
        properties: { share_count: { type: "string" } },
        required: ["share_count"],
        additionalProperties: false
      }
      engine = responses_structured_engine_class.new
      boxcar = described_class.new(engine:, json_schema: schema)

      result = boxcar.run("extract shares")

      expect(result).to eq({ "share_count" => "12,321,999" })
      expect(engine.calls.length).to eq(1)
      expect(engine.calls.first[:kwargs][:response_format]).to eq(
        {
          type: "json_schema",
          json_schema: {
            name: "boxcars_json_output",
            strict: true,
            schema: {
              "type" => "object",
              "properties" => { "share_count" => { "type" => "string" } },
              "required" => ["share_count"],
              "additionalProperties" => false
            }
          }
        }
      )
    end

    it "accepts string-keyed stop values in native structured generation" do
      schema = {
        type: "object",
        properties: { share_count: { type: "string" } },
        required: ["share_count"],
        additionalProperties: false
      }
      engine = native_structured_engine_class.new
      boxcar = described_class.new(engine:, json_schema: schema)

      boxcar.generate(input_list: [{ input: "extract shares", "stop" => ["DONE"] }])

      expect(engine.calls.length).to eq(1)
      expect(engine.calls.first[:kwargs][:stop]).to eq(["DONE"])
    end

    it "raises when native structured generation is called with an empty input list" do
      schema = {
        type: "object",
        properties: { share_count: { type: "string" } },
        required: ["share_count"],
        additionalProperties: false
      }
      engine = native_structured_engine_class.new
      boxcar = described_class.new(engine:, json_schema: schema)

      expect do
        boxcar.generate(input_list: [])
      end.to raise_error(Boxcars::ArgumentError, /requires at least one input hash/)
    end
  end
end
