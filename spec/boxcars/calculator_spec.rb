# frozen_string_literal: true

RSpec.describe Boxcars::Calculator do
  context "without openai api key" do
    it "raises an error", :skip_tokens do
      expect do
        described_class.new.run("1 + 1")
      end.to raise_error(Boxcars::ConfigurationError)
    end
  end

  context "with openai api key" do
    it "can do hard math" do
      VCR.use_cassette("calculator") do
        expect(described_class.new
          .run("what is 2.173 to the power of 22.1 then diveded by 27.2 to 5 significant digits?")).to eq("1033834.56373")
      end
    end

    it "can do easy math" do
      VCR.use_cassette("calculator2") do
        expect(described_class.new.run("what is 1 plus 2?")).to eq("3")
      end
    end
  end
end
