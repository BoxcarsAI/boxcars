# frozen_string_literal: true

RSpec.describe Boxcars::ConductorExecuter do
  # engine = Boxcars::OpenAIEngine.new
  # search = Boxcars::Serp.new
  # calculator = Boxcars::Calculator.new(engine: engine)
  # conductor = Boxcars::Conductor(engine: engine, boxcars: [search, calculator])

  # conductor.run("what is the square root of 100?")

  # # if we had a default engine, we could do this:
  # conductor = Boxcars::Conductor.new(boxcars: [Boxcars::Serp.new, Boxcars::Calculator.new])
  # conductor.run("what is the square root of 100?")

  let(:llm) { Boxcars::LLMOpenAI.new(model: "text-davinci-003") }
  let(:search) { Boxcars::Serp.new }
  let(:calculator) { Boxcars::Calculator.new(llm: llm) }
  let(:conductor) { Boxcars::ZeroShot.new(llm: llm, boxcars: [search, calculator]) }

  let(:conductor_executer) { described_class.new(conductor: conductor, boxcars: [search, calculator]) }

  it "can execute a conductor" do
    VCR.use_cassette("conde") do
      question = "What is pi times the square root of the average temperature in Austin TX in January?"
      expect(conductor_executer.run(question)).to eq("23.298674684623474")
    end
  end

  # it "can execuote openai" do
  #   VCR.use_cassette("openai2") do
  #     question = "What is the square root of the average temperature in Austin TX in January?"
  #     expect(llm.run(question)).to eq("The square root of the average temperature in Austin TX in January is 7.2801098892.")
  #   end
  # end
end
