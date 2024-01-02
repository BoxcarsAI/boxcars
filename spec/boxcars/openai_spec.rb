# frozen_string_literal: true

RSpec.describe Boxcars::Openai do
  context "without an open ai api key" do
    it "raises an error", :skip_tokens do
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

    it "raises an error when nil response" do
      oi = described_class.new
      allow(oi).to receive(:client).and_return(nil)
      expect { oi.run("foobar") }.to raise_error(Boxcars::Error, "OpenAI: No response from API")
    end

    it "raises an when open ai returns one" do
      oi = described_class.new
      allow(oi).to receive(:client).and_return("error" => "foobar")
      expect { oi.run("foobar") }.to raise_error(Boxcars::Error, "OpenAI: foobar")
    end

    it "thinks gpt-4 is a conversation model" do
      expect(described_class.new.conversation_model?("gpt-4")).to be(true)
    end
  end
end
