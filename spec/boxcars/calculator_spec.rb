# frozen_string_literal: true

RSpec.describe Boxcars::Calculator do
  context "without a serpapi api key" do
    it "raises an error" do
      engine = Boxcars::Openai.new
      VCR.use_cassette("calculator") do
        expect(described_class.new(engine: engine)
          .run("what is the square root of 2.173 to the power of 22.1 diveded by 27.2?")).to eq("194.9580048796463")
      end
    end
  end
end
