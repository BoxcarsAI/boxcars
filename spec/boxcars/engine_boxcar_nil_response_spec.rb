require "spec_helper"
require "boxcars"

RSpec.describe Boxcars::EngineBoxcar do
  let(:nil_text_engine_class) do
    Class.new(Boxcars::Engine) do
      def initialize(**kwargs)
        super(description: "NilTextEngine", **kwargs)
      end

      # Return an EngineResult with a single Generation whose text is nil
      def generate(**)
        gen = Boxcars::Generation.new(text: nil)
        Boxcars::EngineResult.new(generations: [[gen]])
      end
    end
  end

  let(:echo_engine_class) do
    Class.new(Boxcars::Engine) do
      def initialize(**kwargs)
        super(description: "EchoEngine", **kwargs)
      end

      def generate(prompts:, **_kwargs)
        generations = prompts.map do |_prompt, inputs|
          [Boxcars::Generation.new(text: inputs[:input].to_s)]
        end
        Boxcars::EngineResult.new(generations:)
      end
    end
  end

  it "does not raise when engine returns nil text and reports error on empty response" do
    prompt = Boxcars::Prompt.new(
      template: "Q: %<input>s",
      input_variables: [:input],
      output_variables: [:answer]
    )
    box = described_class.new(prompt: prompt, engine: nil_text_engine_class.new, description: "test")

    expect do
      rv = box.call(inputs: { input: "hello" })
      expect(rv).to be_a(Hash)
      expect(rv.keys).to include(:answer)
      # After retries, EngineBoxcar returns an error string; ensure it indicates empty response
      expect(rv[:answer].to_s).to match(/Empty response from engine/)
    end.not_to raise_error
  end

  it "returns one output hash per input for apply" do
    prompt = Boxcars::Prompt.new(
      template: "Q: %<input>s",
      input_variables: [:input],
      output_variables: [:answer]
    )
    box = described_class.new(prompt: prompt, engine: echo_engine_class.new, description: "test")
    outputs = box.apply(input_list: [{ input: "one" }, { input: "two" }])
    expect(outputs).to eq([{ answer: "one" }, { answer: "two" }])
  end

  it "returns an empty output list for empty apply input" do
    prompt = Boxcars::Prompt.new(
      template: "Q: %<input>s",
      input_variables: [:input],
      output_variables: [:answer]
    )
    box = described_class.new(prompt: prompt, engine: echo_engine_class.new, description: "test")
    expect(box.apply(input_list: [])).to eq([])
  end

  it "raises when generate is called with an empty input list" do
    prompt = Boxcars::Prompt.new(
      template: "Q: %<input>s",
      input_variables: [:input],
      output_variables: [:answer]
    )
    box = described_class.new(prompt: prompt, engine: nil_text_engine_class.new, description: "test")

    expect do
      box.generate(input_list: [])
    end.to raise_error(Boxcars::ArgumentError, /requires at least one input hash/)
  end
end
