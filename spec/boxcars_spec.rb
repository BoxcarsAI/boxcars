# frozen_string_literal: true

RSpec.describe Boxcars do
  it "has a version number" do
    expect(Boxcars::VERSION).not_to be_nil
  end

  describe "#configure" do
    let(:openai_access_token) { "abc123" }
    let(:serpapi_api_key) { "serp123" }
    let(:organization_id) { "def456" }

    before do
      described_class.configure do |config|
        config.openai_access_token = openai_access_token
        config.serpapi_api_key = serpapi_api_key
        config.organization_id = organization_id
      end
    end

    it "returns the openai access token" do
      expect(described_class.configuration.openai_access_token).to eq(openai_access_token)
    end

    it "returns the openai organization id" do
      expect(described_class.configuration.organization_id).to eq(organization_id)
    end

    it "returns the serpapi api key" do
      expect(described_class.configuration.serpapi_api_key).to eq(serpapi_api_key)
    end
  end
end
