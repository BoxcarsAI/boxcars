# frozen_string_literal: true

RSpec.describe Boxcars::URLText do
  context "with valid urls" do
    it "can get HTML URL" do
      VCR.use_cassette("url_text") do
        expect(described_class.new
          .run("https://en.wikipedia.org/wiki/Miss_Meyers")).to include("fellow Hall of Famer")
      end
    end

    it "can get text URL" do
      VCR.use_cassette("url_text2") do
        turl = "https://gist.githubusercontent.com/tabrez-syed/1c31a11dde355a0974d9c3a3ee97988c/raw/09e5c5657d587b913848529be511c6a88bf65667/gistfile1.txt"
        expect(described_class.new.run(turl)).to include("Devry University")
      end
    end

    it "can return structured result when needed" do
      VCR.use_cassette("url_text2") do
        turl = "https://gist.githubusercontent.com/tabrez-syed/1c31a11dde355a0974d9c3a3ee97988c/raw/09e5c5657d587b913848529be511c6a88bf65667/gistfile1.txt"
        result = described_class.new.run_result(turl)
        expect(result).to be_a(Boxcars::Result)
        expect(result.answer).to include("Devry University")
      end
    end
  end
end
