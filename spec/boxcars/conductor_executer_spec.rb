# frozen_string_literal: true

RSpec.describe Boxcars::ConductorExecuter do
  let(:llm) { Boxcars::LLMOpenAI.new }
  let(:search) { Boxcars::Serp.new }
  let(:calculator) { Boxcars::Calculator.new(llm: llm) }
  let(:conductor) { Boxcars::ZeroShot.new(llm: llm, boxcars: [search, calculator]) }

  let(:conductor_executer) { described_class.new(conductor: conductor, boxcars: [search, calculator]) }

  it "can execute a conductor" do
    VCR.use_cassette("conde") do
      question = "What is the square root of the average temperature in Austin TX in January?"
      expect(conductor_executer.run(question)).to eq("The square root of the average temperature in Austin TX in January is 7.43.")
    end
  end
end
