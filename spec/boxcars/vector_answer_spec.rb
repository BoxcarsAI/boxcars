# frozen_string_literal: true

RSpec.describe Boxcars::VectorAnswer do
  context "with mocked vector store" do
    let(:search_result) do
      "For work, we provide you with a laptop that suits your job. HR will give you further info.\n- **Workplace**: \nwe've built a pretty nice office to make sure you like being at Blendle HQ."
    end
    # let(:vector_search) { instance_double(described_class) }
    let(:vector_answer) { described_class.new(embeddings: 'foo', vector_documents: 'bar') }

    before do
      # allow(described_class).to receive(:new).and_return(vector_search)
      allow(vector_answer).to receive(:get_search_content).and_return(search_result)
    end

    it "can answer a question from content" do
      VCR.use_cassette("vector_answer") do
        expect(vector_answer.run("Will I get a laptop?")).to include("you will be provided with a laptop")
      end
    end
  end
end
