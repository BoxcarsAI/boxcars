# frozen_string_literal: true

RSpec.describe Boxcars::ZeroShot do
  let(:engine) { Boxcars::Openai.new }
  let(:search) { Boxcars::GoogleSearch.new }
  let(:calculator) { Boxcars::Calculator.new(engine: engine) }

  it "can execute a train" do
    train = described_class.new(engine: engine, boxcars: [search, calculator])

    VCR.use_cassette("zeroshot") do
      question = "What is pi times the square root of the average temperature in Austin TX in January?"
      expect(train.run(question)).to eq("25.132741228718345")
    end
  end

  context "with sample helpdesk app" do
    let(:helpdesk) { Boxcars::ActiveRecord.new(models: [Comment, Ticket, User], name: "helpdesk") }

    it "can use a train to answer a question" do
      train = described_class.new(boxcars: [helpdesk, calculator, search])
      VCR.use_cassette("zeroshot2") do
        question = "Count the comments from John for open tickets and multiply by pi to 5 decimal places."
        expect(train.run(question)).to eq("6.28319")
      end
    end
  end
end
