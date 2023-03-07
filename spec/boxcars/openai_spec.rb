# frozen_string_literal: true

RSpec.describe Boxcars::Openai do
  context "without an open ai api key" do
    it "raises an error", skip_tokens: true do
      expect do
        described_class.new.client(prompt: "write a poem")
      end.to raise_error(Boxcars::ConfigurationError)
    end
  end

  context "with an open ai api key" do
    it "can write a short poem" do
      VCR.use_cassette("openai") do
        expect(described_class.new.run("write a haiku about love")).to eq("Love, a gentle breeze\nWhispers sweet nothings in ear\nHeart beats as one, true")
      end
    end
  end
end
