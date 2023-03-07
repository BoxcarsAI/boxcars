# frozen_string_literal: true

RSpec.describe Boxcars::GoogleSearch do
  context "without a serpapi api key" do
    it "raises an error", skip_tokens: true do
      expect do
        described_class.new(serpapi_api_key: nil).run("what temperature is it in Austin?")
      end.to raise_error(Boxcars::ConfigurationError)
    end
  end

  context "with a serpapi api key" do
    it "gets the temperature in Austin" do
      VCR.use_cassette("serp") do
        expect(described_class.new.run("what temperature is it in Austin TX right now?")).to eq("65°")
      end
    end
  end
end
