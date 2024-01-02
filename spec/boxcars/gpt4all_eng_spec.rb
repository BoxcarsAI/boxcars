# frozen_string_literal: true

RSpec.describe Boxcars::Gpt4allEng do
  context "with gpt4all gem" do
    before do
      unless ENV["CALL_GPT4ALL"] == "true"
        gc = instance_double(Gpt4all::ConversationalAI)
        allow(Gpt4all::ConversationalAI).to receive(:new).and_return(gc)
        allow(gc).to receive(:prepare_resources).with(force_download: false).and_return(true)
        allow(gc).to receive_messages(start_bot: true, stop_bot: true)
        allow(gc).to receive(:prompt).with("write a haiku about love").and_return("Love, like poetry is fine")
      end
    end

    it "can write a short poem" do
      expect(described_class.new.run("write a haiku about love")).to include("Love, like poetry")
    end
  end
end
