# frozen_string_literal: true

RSpec.describe Boxcars::Anthropic do
  context "without an anthropic api key" do
    it "raises an error", :skip_tokens do
      expect do
        described_class.new.client(prompt: "write a poem")
      end.to raise_error(Boxcars::ConfigurationError)
    end
  end

  context "with an anthropic api key" do
    it "can write a short poem" do
      VCR.use_cassette("anthropic") do
        expect(described_class.new.run("write a haiku about love")).to include("Love")
      end
    end

    it "raises an error when nil response" do
      an = described_class.new
      allow(an).to receive(:client).and_return(nil)
      expect { an.run("foobar") }.to raise_error(Boxcars::Error, "Anthropic: No response from API")
    end

    it "raises an when open ai returns one" do
      an = described_class.new
      allow(an).to receive(:client).and_return("error" => "foobar")
      expect { an.run("foobar") }.to raise_error(Boxcars::Error, "Anthropic: foobar")
    end
  end
end
