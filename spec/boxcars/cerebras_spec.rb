# frozen_string_literal: true

RSpec.describe Boxcars::Cerebras do
  context "without a cerebras api key" do
    it "raises an error", :skip_tokens do
      expect do
        described_class.new.client(prompt: "write a poem")
      end.to raise_error(Boxcars::ConfigurationError)
    end
  end

  # context "with a cerebras api key" do
  #   it "can write a short poem" do
  #     VCR.use_cassette("cerebras") do
  #       expect(described_class.new.run("write a haiku about love")).to eq("Softly glowing flame\nWarming heart and gentle soul\nLove's eternal kiss")
  #     end
  #   end
  # end
end
