# frozen_string_literal: true

RSpec.describe Boxcars::Calculator do
  context "without a serpapi api key" do
    it "raises an error" do
      engine = Boxcars::Openai.new
      VCR.use_cassette("calculator") do
        expect(described_class.new(engine: engine)
          .run("what is 2.173 to the power of 22.1 then diveded by 27.2 to 5 significant digits?")).to eq("1033834.56373")
      end
    end
  end
end
