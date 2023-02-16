# frozen_string_literal: true

RSpec.describe Boxcars::ConductorExecuter do
  let(:engine) { Boxcars::Openai.new(model: "text-davinci-003") }
  let(:search) { Boxcars::Serp.new }
  let(:calculator) { Boxcars::Calculator.new(engine: engine) }
  let(:conductor) { Boxcars::ZeroShot.new(engine: engine, boxcars: [search, calculator]) }

  let(:conductor_executer) { described_class.new(conductor: conductor, boxcars: [search, calculator]) }

  it "can execute a conductor" do
    VCR.use_cassette("conde") do
      question = "What is pi times the square root of the average temperature in Austin TX in January?"
      expect(conductor_executer.run(question)).to eq("23.128609092183716")
    end
  end

  # it "can execuote openai" do
  #   VCR.use_cassette("openai2") do
  #     question = "What is the square root of the average temperature in Austin TX in January?"
  #     expect(engine.run(question)).to eq("The square root of the average temperature in Austin TX in January is 7.2801098892.")
  #   end
  # end
end
