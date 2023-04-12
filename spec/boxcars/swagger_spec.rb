# frozen_string_literal: true

RSpec.describe Boxcars::Swagger do
  context "with openai api key" do
    let(:swagger_url) { "https://app.mightycanary.com/api-docs/v1/swagger.yaml" }
    let(:mc_api_token) { ENV.fetch("MC_API_TOKEN", "") }

    it "can do simple API call from swagger file" do
      VCR.use_cassette("swagger") do
        expect(described_class.new
          .run(question: "How many Sentries are there?", swagger_url: swagger_url,
               context: "API_token: #{mc_api_token}")).to eq("194")
      end
    end

    it "can do easy question" do
      VCR.use_cassette("swagger2") do
        expect(described_class.new.run(question: "what is 1 plus 2?", context: "", swagger_url: swagger_url)).to include("3")
      end
    end

    it "can answer a question about the API" do
      VCR.use_cassette("swagger3") do
        expect(described_class.new.run(question: "describe the available APIs for sentries", context: "don't forget to require the yaml library", swagger_url: swagger_url)).to include("api/v1/sentries")
      end
    end
  end
end
