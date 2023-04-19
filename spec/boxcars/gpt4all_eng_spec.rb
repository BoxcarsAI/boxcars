# frozen_string_literal: true

RSpec.describe Boxcars::Gpt4allEng do
  context "with gpt4all gem" do
    before do
      unless ENV["CALL_GPT4ALL"] == "true"
        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(Gpt4all).to receive(:start_bot).and_return(true)
        allow_any_instance_of(Gpt4all).to receive(:stop_bot).and_return(true)
        allow_any_instance_of(Gpt4all).to receive(:promt).and_return('Love, like poetry')
        # rubocop:enable RSpec/AnyInstance
      end
    end

    it "can write a short poem" do
      expect(described_class.new.run("write a haiku about love")).to include("Love, like poetry")
    end
  end
end
