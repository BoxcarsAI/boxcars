# frozen_string_literal: true

RSpec.describe Boxcars::Calculator do
  context "without a serpapi api key" do
    it "raises an error" do
      puts "Calculator spec".colorize(:red)
      llm = Boxcars::LLMOpenAI.new
      VCR.use_cassette("calculator") do
        expect(Boxcars::Calculator.new(llm: llm)
          .run("what is the square root of 2 to the power of 22 diveded by 27?")).to eq("Answer: 394.13703200790457")
      end
    end
  end
end
