# frozen_string_literal: true

RSpec.describe Boxcars::Ollama do
  context "with local" do
    it "can write a short poem" do
      VCR.use_cassette("ollama") do
        expect(described_class.new.run("write a haiku about love")).to eq("Softly glowing flame\nWarming hearts and gentle souls\nLove's sweet, tender name")
      end
    end

    it "raises an error when nil response" do
      oi = described_class.new
      allow(oi).to receive(:client).and_return(nil)
      expect { oi.run("foobar") }.to raise_error(Boxcars::Error, "Ollama: No response from API")
    end

    it "thinks ollama is a conversation model" do
      expect(described_class.new.conversation_model?("llama3")).to be(true)
    end
  end
end
