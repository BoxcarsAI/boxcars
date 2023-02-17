# frozen_string_literal: true

RSpec.describe Boxcars::Conductor do
  let(:search) { Boxcars::Serp.new }
  let(:calculator) { Boxcars::Calculator.new }
  let(:conductor) { Boxcars.default_conductor.new(boxcars: [search, calculator]) }

  it "can execute the default conductor" do
    VCR.use_cassette("conductor") do
      question = "how many days in a year?"
      expect(conductor.run(question)).to eq("There are 365 days in a year.")
    end
  end
end
