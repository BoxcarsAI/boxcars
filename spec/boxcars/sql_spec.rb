# frozen_string_literal: true

RSpec.describe Boxcars::SQL do
  context "without a serpapi api key" do
    it "raises an error" do
      expect do
        Boxcars::Serp.new(serpapi_api_key: nil).run("what temperature is it in Austin?")
      end.to raise_error(Boxcars::ConfigurationError)
    end
  end
end
