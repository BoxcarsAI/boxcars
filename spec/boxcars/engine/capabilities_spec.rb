# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Engine capabilities" do
  describe Boxcars::Engine do
    let(:engine_class) do
      Class.new(described_class) do
        def run(_question)
          "ok"
        end
      end
    end

    it "provides conservative default capabilities" do
      engine = engine_class.new(description: "test")

      expect(engine.capabilities).to include(
        tool_calling: false,
        structured_output_json_schema: false,
        native_json_object: false,
        responses_api: false
      )
      expect(engine.supports?(:tool_calling)).to be(false)
      expect(engine.supports?(:missing_capability)).to be(false)
    end
  end

  describe Boxcars::Openai do
    it "advertises tool-calling capabilities for chat models" do
      engine = described_class.new(model: "gpt-4o-mini")

      expect(engine.supports?(:tool_calling)).to be(true)
      expect(engine.supports?(:structured_output_json_schema)).to be(true)
      expect(engine.supports?(:native_json_object)).to be(true)
      expect(engine.supports?(:responses_api)).to be(false)
    end

    it "advertises responses API capability for gpt-5 models" do
      engine = described_class.new(model: "gpt-5-mini")

      expect(engine.supports?(:tool_calling)).to be(true)
      expect(engine.supports?(:structured_output_json_schema)).to be(true)
      expect(engine.supports?(:responses_api)).to be(true)
    end

    it "does not advertise tool-calling for legacy completion models" do
      engine = described_class.new(model: "text-davinci-003")

      expect(engine.supports?(:tool_calling)).to be(false)
      expect(engine.supports?(:structured_output_json_schema)).to be(false)
      expect(engine.supports?(:native_json_object)).to be(false)
    end
  end
end
