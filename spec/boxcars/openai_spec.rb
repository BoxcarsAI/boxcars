# frozen_string_literal: true

RSpec.describe Boxcars::Openai do
  context "without an open ai api key" do
    before do
      allow(ENV).to receive(:fetch).with('OPENAI_ACCESS_TOKEN', nil).and_return(nil)
    end

    it "raises an error" do
      expect do
        described_class.new.client(prompt: "write a poem")
      end.to raise_error(Boxcars::ConfigurationError)
    end
  end

  context "with an open ai api key" do
    it "can write a short poem" do
      VCR.use_cassette("openai") do
        expect(described_class.new.run("write a haiku about love")).to eq("A love so pure and true \nMy heart beats just for you \nYour love is all I need")
      end
    end
  end
end
