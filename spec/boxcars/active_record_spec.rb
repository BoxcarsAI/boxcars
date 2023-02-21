# frozen_string_literal: true

RSpec.describe Boxcars::ActiveRecord do
  context "without active record models" do
    it "raises an error with improper model arguments" do
      expect do
        described_class.new(models: [String, Integer])
      end.to raise_error(Boxcars::ArgumentError)
    end

    it "raises an error with empty model arguments" do
      expect do
        described_class.new(models: [])
      end.to raise_error(Boxcars::ArgumentError)
    end
  end

  context "with sample helpdesk app all models" do
    Boxcars.configuration.log_prompts = true
    boxcar = described_class.new

    it "can count comments from john" do
      VCR.use_cassette("ar1") do
        expect(boxcar.run("count how many comments are there from John?")).to eq("Answer: 2")
      end
    end

    it "can find the last comment content to the first post" do
      VCR.use_cassette("ar2") do
        expect(boxcar.run("What is the content of the last comment for the first ticket?")).to include("johns second comment")
      end
    end
  end

  context "with sample helpdesk app some models" do
    Boxcars.configuration.log_prompts = true
    boxcar = described_class.new(models: [Comment, Ticket, User])

    it "can count comments from john" do
      VCR.use_cassette("ar3") do
        expect(boxcar.run("count of comments from John?")).to eq("Answer: 2")
      end
    end

    it "can find the last comment content to the first post" do
      VCR.use_cassette("ar4") do
        expect(boxcar.run("What is the content of the last comment for the first ticket?")).to include("johns second comment")
      end
    end
  end

end
