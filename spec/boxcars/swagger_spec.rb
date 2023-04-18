# frozen_string_literal: true

RSpec.describe Boxcars::Swagger do
  context "with openai api key" do
    let(:swagger_url) { "https://petstore.swagger.io/v2/swagger.json" }
    let(:api_token) { "secret-key" }
    let(:my_pet) { "952809" }

    it "can do simple API call from swagger file" do
      VCR.use_cassette("swagger") do
        expect(described_class.new(swagger_url: swagger_url, context: "API_token: #{api_token}")
          .run("I was watching pet with id #{my_pet}. Has she sold?")).to include("Yes")
      end
    end

    it "can do easy question" do
      VCR.use_cassette("swagger2") do
        expect(described_class.new(swagger_url: swagger_url, context: "API_token: #{api_token}").run("what is 1 plus 2?")).to include("3")
      end
    end

    it "can answer a question about the API" do
      VCR.use_cassette("swagger3") do
        expect(described_class.new(swagger_url: swagger_url).run("describe the available APIs for pets")).to include("/pet/")
      end
    end
  end
end
