# frozen_string_literal: true

RSpec.describe Boxcars::ActiveRecord do
  context "with sample helpdesk app" do
    Boxcars.configuration.log_prompts = true
    boxcar = described_class.new

    it "can count responses from john" do
      VCR.use_cassette("ar1") do
        expect(boxcar.run("how many responses are there from John?")).to eq("Answer: 2")
      end
    end

    it "can find the last response to the first post" do
      VCR.use_cassette("ar2") do
        expect(boxcar.run("What is the last response for the first ticket?")).to include("johns second comment")
      end
    end
  end
end
