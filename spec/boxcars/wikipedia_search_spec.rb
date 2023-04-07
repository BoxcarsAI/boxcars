# frozen_string_literal: true

RSpec.describe Boxcars::WikipediaSearch do
  context "with wikipedia" do
    it "gets the county of Austin" do
      VCR.use_cassette("wiki") do
        expect(described_class.new.run("What county is Austin in?")).to include("Travis")
      end
    end

    it "gets the capital of Arizona" do
      VCR.use_cassette("wiki2") do
        expect(described_class.new.run("What is the capital of Arizona?")).to include("Phoenix")
      end
    end
  end
end
