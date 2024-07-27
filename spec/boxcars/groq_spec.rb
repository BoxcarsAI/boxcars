# frozen_string_literal: true

RSpec.describe Boxcars::Groq do
  context "without an groq api key" do
    it "raises an error", :skip_tokens do
      expect do
        described_class.new.client(prompt: "write a poem")
      end.to raise_error(Boxcars::ConfigurationError)
    end
  end

  context "with an groq api key" do
    # it "can write a short poem" do
    #   VCR.use_cassette("groq") do
    #     expect(described_class.new.run("write a haiku about love")).to eq("Softly glowing flame\nWarming heart and gentle soul\nLove's eternal fire")
    #   end
    # end

    it "raises an error when nil response" do
      oi = described_class.new
      allow(oi).to receive(:client).and_return(nil)
      expect { oi.run("foobar") }.to raise_error(Boxcars::Error, "Groq: No response from API")
    end

    it "raises invalid_key when groq returns one" do
      oi = described_class.new
      allow(oi).to receive(:client).and_return("error" => { 'code' => 'invalid_api_key', 'message' => 'bad' })
      expect { oi.run("foobar") }.to raise_error(Boxcars::KeyError, "GROQ_API_TOKEN not valid")
    end

    it "thinks gpt-4 is a conversation model" do
      expect(described_class.new.conversation_model?("gpt-4")).to be(true)
    end
  end
end
