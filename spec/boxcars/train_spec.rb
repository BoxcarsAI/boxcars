# frozen_string_literal: true

RSpec.describe Boxcars::Train do
  let(:search) { Boxcars::GoogleSearch.new }
  let(:calculator) { Boxcars::Calculator.new }
  let(:train) { Boxcars.train.new(boxcars: [search, calculator]) }

  it "raises for abstract extract_boxcar_and_input implementation" do
    abstract_train = described_class.allocate

    expect { abstract_train.extract_boxcar_and_input("output") }
      .to raise_error(NotImplementedError, /must implement #extract_boxcar_and_input/)
  end

  it "can execute the default train" do
    VCR.use_cassette("train") do
      question = "how many days in a year?"
      expect(train.run(question)).to include("365 days")
    end
  end
end
