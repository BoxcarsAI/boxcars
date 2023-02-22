# frozen_string_literal: true

RSpec.describe Boxcars::ZeroShot do
  let(:engine) { Boxcars::Openai.new }
  let(:search) { Boxcars::GoogleSearch.new }
  let(:calculator) { Boxcars::Calculator.new(engine: engine) }
  let(:train) { described_class.new(engine: engine, boxcars: [search, calculator]) }

  it "can execute a train" do
    VCR.use_cassette("zeroshot") do
      question = "What is pi times the square root of the average temperature in Austin TX in January?"
      expect(train.run(question)).to eq("25.132741228718345")
    end
  end

  context "with sample helpdesk app" do
    helpdesk = Boxcars::ActiveRecord.new(models: [Comment, Ticket, User], name: "helpdesk")
    new_train = described_class.new(boxcars: [helpdesk, Boxcars::Calculator.new, Boxcars::GoogleSearch.new])
    it "can use a train to answer a question" do
      VCR.use_cassette("zeroshot2") do
        question = "Count the comments from John for open tickets and multiply by pi to 5 decimal places."
        expect(new_train.run(question)).to eq("6.28319")
      end
    end
  end
end
