# frozen_string_literal: true

RSpec.describe Boxcars::ZeroShot do
  let(:engine) { Boxcars::Openai.new }
  let(:search) { Boxcars::Serp.new }
  let(:calculator) { Boxcars::Calculator.new(engine: engine) }
  let(:train) { described_class.new(engine: engine, boxcars: [search, calculator]) }

  it "can execute a train" do
    VCR.use_cassette("zeroshot") do
      question = "What is pi times the square root of the average temperature in Austin TX in January?"
      expect(train.run(question)).to eq("25.132741228718345")
    end
  end
end
