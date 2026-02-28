# frozen_string_literal: true

RSpec.describe Boxcars::RubyCalculator do
  context "with openai api key" do
    it "can do hard math" do
      expect(described_class.new
        .run("((2.173 ** 22.1) / 27.2).round(5)")).to eq("1033834.56373")
    end

    it "can do easy math" do
      expect(described_class.new.run("1+2")).to eq("3")
    end

    it "can return structured result when needed" do
      result = described_class.new.run_result("1+2")
      expect(result).to be_a(Boxcars::Result)
      expect(result.answer).to eq("3")
    end

    it "can be run from a train" do
      bc = described_class.new
      train = Boxcars::XMLZeroShot.new(boxcars: [bc])
      VCR.use_cassette("ruby_calculator") do
        expect(train.run("what is 2.173 to the power of 22.1 then diveded by 27.2?")).to eq("1033834.5637329388")
      end
    end
  end
end
