# frozen_string_literal: true

RSpec.describe Boxcars::Swagger do
  context "with openai api key" do
    let(:swagger_url) { "https://app.mightycanary.com/api-docs/v1/swagger.yaml" }
    let(:mc_api_token) { ENV.fetch("MC_API_TOKEN", "") }

    it "can do simple API call from swagger file" do
      VCR.use_cassette("swagger") do
        expect(described_class.new
          .run(question: "How many Sentires are there?", swagger_url: swagger_url,
               context: "API_token: #{mc_api_token}, sentry api path: api/v1/sentries")).to eq("194")
      end
    end

    it "can do easy question" do
      VCR.use_cassette("swagger2") do
        expect(described_class.new.run(question: "what is 1 plus 2?", context: "", swagger_url: swagger_url)).to include("3")
      end
    end
  end
end
