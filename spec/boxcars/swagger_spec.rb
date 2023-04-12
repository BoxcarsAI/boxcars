# frozen_string_literal: true

RSpec.describe Boxcars::Swagger do
  context "with openai api key" do
    let(:swagger_url) { "https://petstore.swagger.io/v2/swagger.json" }
    let(:api_token) { "secret-key" }
    let(:my_pet) { "40010473" }

    it "can do simple API call from swagger file" do
      VCR.use_cassette("swagger") do
        expect(described_class.new
          .run(question: "I was watching pet with id #{my_pet}. Has she sold?", swagger_url: swagger_url,
               context: "API_token: #{api_token}")).to eq("Yes")
      end
    end

    it "can do easy question" do
      VCR.use_cassette("swagger2") do
        expect(described_class.new.run(question: "what is 1 plus 2?", context: "", swagger_url: swagger_url)).to include("3")
      end
    end

    it "can answer a question about the API" do
      VCR.use_cassette("swagger3") do
        expect(described_class.new.run(question: "describe the available APIs for pets", context: "don't forget to require the yaml library", swagger_url: swagger_url)).to include("/pet/")
      end
    end
  end
end
