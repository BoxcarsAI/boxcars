# frozen_string_literal: true

RSpec.describe Boxcars::Google do
  context "without a google api key" do
    it "raises an error", :skip_tokens do
      expect do
        described_class.new.client(prompt: "write a poem")
      end.to raise_error(Boxcars::ConfigurationError)
    end
  end
end
