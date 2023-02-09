# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
RSpec.describe Boxcars do
  it "has a version number" do
    expect(Boxcars::VERSION).not_to be nil
  end

  describe "#configure" do
    let(:openai_access_token) { "abc123" }
    let(:serpapi_api_key) { "serp123" }
    let(:organization_id) { "def456" }

    before do
      Boxcars.configure do |config|
        config.openai_access_token = openai_access_token
        config.serpapi_api_key = serpapi_api_key
        config.organization_id = organization_id
      end
    end

    it "returns the config" do
      expect(Boxcars.configuration.openai_access_token).to eq(openai_access_token)
      expect(Boxcars.configuration.serpapi_api_key).to eq(serpapi_api_key)
      expect(Boxcars.configuration.organization_id).to eq(organization_id)
    end

    context "without an open ai api key" do
      it "raises an error" do
        expect do
          Boxcars::LLMOpenAI.new.client(prompt: "write a poem",
                                        openai_access_token: nil)
        end.to raise_error(Boxcars::ConfigurationError)
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
