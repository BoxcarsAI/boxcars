# frozen_string_literal: true

require "spec_helper"

RSpec.describe Boxcars::ToolCallingTrain do
  let(:calculator_boxcar_class) do
    Class.new(Boxcars::Boxcar) do
      def initialize(**kwargs)
        super(
          name: "Calculator",
          description: "Performs math",
          parameters: {
            question: { type: :string, required: true, description: "Math expression" }
          },
          **kwargs
        )
      end

      def call(inputs:)
        answer = case inputs[:question]
                 when "2+2" then "4"
                 else "unknown"
                 end
        { answer: Boxcars::Result.from_text(answer) }
      end

      def apply(input_list:)
        input_list
      end
    end
  end

  let(:calculator_boxcar) { calculator_boxcar_class.new }

  let(:fake_tool_engine_class) do
    Class.new(Boxcars::Engine) do
      attr_reader :calls

      def initialize(responses:)
        @responses = responses.dup
        @calls = []
        super(description: "fake tool engine")
      end

      def capabilities
        super.merge(tool_calling: true)
      end

      def client(prompt:, inputs: {}, **kwargs)
        @calls << { prompt:, inputs:, kwargs: }
        @responses.shift || raise("No fake response left")
      end

      def run(_question)
        raise NotImplementedError
      end
    end
  end

  let(:unsupported_engine_class) do
    Class.new(Boxcars::Engine) do
      def initialize
        super(description: "unsupported")
      end

      def run(_question)
        "nope"
      end
    end
  end

  let(:fake_responses_tool_engine_class) do
    Class.new(Boxcars::Engine) do
      attr_reader :calls

      def initialize(responses:)
        @responses = responses.dup
        @calls = []
        super(description: "fake responses tool engine")
      end

      def capabilities
        super.merge(tool_calling: true, responses_api: true)
      end

      def client(prompt:, inputs: {}, **kwargs)
        @calls << { prompt:, inputs:, kwargs: }
        @responses.shift || raise("No fake response left")
      end

      def run(_question)
        raise NotImplementedError
      end
    end
  end

  describe "#run" do
    it "executes tool calls and returns the final assistant answer" do
      tool_call_name = calculator_boxcar.tool_call_name
      engine = fake_tool_engine_class.new(
        responses: [
          {
            "choices" => [
              {
                "message" => {
                  "role" => "assistant",
                  "content" => nil,
                  "tool_calls" => [
                    {
                      "id" => "call_1",
                      "type" => "function",
                      "function" => {
                        "name" => tool_call_name,
                        "arguments" => '{"question":"2+2"}'
                      }
                    }
                  ]
                }
              }
            ]
          },
          {
            "choices" => [
              {
                "message" => {
                  "role" => "assistant",
                  "content" => "The answer is 4."
                }
              }
            ]
          }
        ]
      )

      train = described_class.new(boxcars: [calculator_boxcar], engine:)
      result = train.run("What is 2+2?")

      expect(result).to eq("The answer is 4.")
      expect(engine.calls.length).to eq(2)

      first_call = engine.calls.first
      expect(first_call[:kwargs][:tool_choice]).to eq("auto")
      expect(first_call[:kwargs][:tools]).to eq([calculator_boxcar.tool_spec])

      second_messages = engine.calls.last[:prompt].as_messages[:messages]
      tool_message = second_messages.find { |m| m[:role] == :tool }
      expect(tool_message).to include(tool_call_id: "call_1", content: "4")
    end

    it "raises when engine does not support tool-calling" do
      train = described_class.new(boxcars: [calculator_boxcar], engine: unsupported_engine_class.new)

      expect { train.run("What is 2+2?") }
        .to raise_error(Boxcars::ArgumentError, /does not support native tool-calling/)
    end

    it "supports Responses API-style function calls (gpt-5 style loop)" do
      tool_call_name = calculator_boxcar.tool_call_name
      engine = fake_responses_tool_engine_class.new(
        responses: [
          {
            "id" => "resp_1",
            "output" => [
              {
                "type" => "function_call",
                "id" => "fc_1",
                "call_id" => "call_1",
                "name" => tool_call_name,
                "arguments" => '{"question":"2+2"}'
              }
            ]
          },
          {
            "id" => "resp_2",
            "output" => [],
            "output_text" => "The answer is 4."
          }
        ]
      )

      train = described_class.new(boxcars: [calculator_boxcar], engine:)
      result = train.run("What is 2+2?")

      expect(result).to eq("The answer is 4.")
      expect(engine.calls.length).to eq(2)

      second_call = engine.calls.last
      expect(second_call[:kwargs][:previous_response_id]).to eq("resp_1")
      expect(second_call[:kwargs][:response_input]).to eq(
        [
          {
            type: "function_call_output",
            call_id: "call_1",
            output: "4"
          }
        ]
      )
    end
  end
end
