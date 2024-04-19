# frozen_string_literal: true

RSpec.describe Boxcars::Cohere do
  context "without an cohere api key" do
    it "raises an error", :skip_tokens do
      expect do
        described_class.new.client(prompt: "write a poem")
      end.to raise_error(Boxcars::ConfigurationError)
    end
  end

  context "with an cohere api key" do
    it "can write a short poem" do
      VCR.use_cassette("cohere") do
        expect(described_class.new.run("write a haiku about love")).to include("Love")
      end
    end

    it "raises an error when nil response" do
      an = described_class.new
      allow(an).to receive(:client).and_return(nil)
      expect { an.run("foobar") }.to raise_error(Boxcars::Error, "Cohere: No response from API")
    end

    it "raises an error when cohere returns one" do
      an = described_class.new
      allow(an).to receive(:client).and_return(error: "foobar")
      expect { an.run("foobar") }.to raise_error(Boxcars::Error, "Cohere: foobar")
    end
  end
end
