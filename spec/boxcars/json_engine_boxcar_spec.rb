# frozen_string_literal: true

RSpec.describe Boxcars::JSONEngineBoxcar do
  context "with default prompt" do
    boxcar = described_class.new(wanted_data: '"share_count": "the number of shares"')

    it "can get the number of shares" do
      VCR.use_cassette("jeb1") do
        expect(boxcar.run("{ at last count, there were 12,321,999 shares total }")).to eq({ "share_count" => "12,321,999" })
      end
    end
  end
end
