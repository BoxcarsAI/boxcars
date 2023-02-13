# frozen_string_literal: true

RSpec.describe Boxcars::Serp do
  context "without a serpapi api key" do
    it "raises an error" do
      expect do
        described_class.new(serpapi_api_key: nil).run("what temperature is it in Austin?")
      end.to raise_error(Boxcars::ConfigurationError)
    end

    it "gets the temperature in Austin" do
      VCR.use_cassette("serp") do
        expect(described_class.new.run("what temperature is it in Austin TX right now?")).to eq("50 °F")
      end
    end
  end
end
