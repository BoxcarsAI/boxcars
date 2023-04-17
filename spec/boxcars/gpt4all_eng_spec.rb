# frozen_string_literal: true

RSpec.describe Boxcars::Gpt4allEng do
  context "with an open ai api key" do
    before do
      unless ENV["CALL_GPT4ALL"] == "true"
        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(IO).to receive(:read_nonblock).and_return('Bot is ready >', 'Love, like poetry', '>')
        # rubocop:enable RSpec/AnyInstance
      end
    end

    it "can write a short poem" do
      VCR.use_cassette("gpt4all") do
        expect(described_class.new.run("write a haiku about love")).to include("Love, like poetry")
      end
    end
  end
end
