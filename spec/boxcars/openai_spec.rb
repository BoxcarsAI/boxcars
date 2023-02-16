# frozen_string_literal: true

RSpec.describe Boxcars::Openai do
  context "without an open ai api key" do
    it "raises an error" do
      expect do
        described_class.new.client(prompt: "write a poem", openai_access_token: nil)
      end.to raise_error(Boxcars::ConfigurationError)
    end

    it "can write a short poem" do
      VCR.use_cassette("openai") do
        expect(described_class.new.run("write a haiku about love")).to eq("A love so pure and true \nMy heart beats just for you \nYour love is all I need")
      end
    end
  end
end
