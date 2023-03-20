# frozen_string_literal: true

RSpec.describe Boxcars::Train do
  let(:search) { Boxcars::GoogleSearch.new }
  let(:calculator) { Boxcars::Calculator.new }
  let(:train) { Boxcars.train.new(boxcars: [search, calculator]) }

  it "can execute the default train" do
    VCR.use_cassette("train") do
      question = "how many days in a year?"
      expect(train.run(question)).to include("365 days")
    end
  end
end
