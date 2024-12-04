# frozen_string_literal: true

RSpec.describe Boxcars::GeminiAi do
  context "without an gemini_ai api key" do
    it "raises an error", :skip_tokens do
      expect do
        described_class.new.client(prompt: "write a poem")
      end.to raise_error(Boxcars::ConfigurationError)
    end
  end

  context "with an gemini_ai api key" do
    it "can write a short poem" do
      VCR.use_cassette("gemini_ai") do
        expect(described_class.new.run("Say Hi.")).to include("Hi")
      end
    end

    it "raises an error when nil response" do
      an = described_class.new
      allow(an).to receive(:client).and_return(nil)
      expect { an.run("foobar") }.to raise_error(Boxcars::Error, "GeminiAI: No response from API")
    end

    it "raises an error when gemini_ai returns one" do
      an = described_class.new
      allow(an).to receive(:client).and_return(error: "foobar")
      expect { an.run("foobar") }.to raise_error(Boxcars::Error, "GeminiAI: foobar")
    end
  end
end
