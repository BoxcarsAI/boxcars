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
end
