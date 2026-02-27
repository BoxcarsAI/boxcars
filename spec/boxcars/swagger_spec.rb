# frozen_string_literal: true

RSpec.describe Boxcars::Swagger do
  describe "prompt template" do
    it "guides API calls through Faraday" do
      template_text = described_class::CTEMPLATE.join("\n")
      expect(template_text).to include("faraday gem")
      expect(template_text).to include("Faraday.get(url)")
      expect(template_text).not_to include("rest-client gem")
    end
  end

  context "with openai api key" do
    let(:swagger_url) { "https://petstore.swagger.io/v2/swagger.json" }
    let(:api_token) { "secret-key" }
    let(:engine) { Boxcars::Openai.new(model: "gpt-3.5-turbo") }

    # the pet api data keeps changing, so we can't use my_pet for testing
    # let(:my_pet) { "952809" }

    # it "can do simple API call from swagger file" do
    #   VCR.use_cassette("swagger") do
    #     expect(described_class.new(swagger_url: swagger_url, context: "API_token: #{api_token}")
    #       .run("I was watching pet with id #{my_pet}. Has she sold?")).to include("Yes")
    #   end
    # end

    it "can do easy question" do
      VCR.use_cassette("swagger2", match_requests_on: %i[method uri]) do
        expect(described_class.new(swagger_url: swagger_url, context: "API_token: #{api_token}", engine: engine)
          .run("what is 1 plus 2?")).to include("3")
      end
    end

    it "can answer a question about the API" do
      VCR.use_cassette("swagger3", match_requests_on: %i[method uri]) do
        expect(described_class.new(swagger_url: swagger_url, engine: engine).run("describe the available APIs for pets")).to include("/pet/")
      end
    end
  end
end
