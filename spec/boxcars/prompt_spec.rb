# frozen_string_literal: true

RSpec.describe Boxcars::Prompt do
  let(:template) { { template: "hi %<you>s!" } }

  context "with a prompt" do
    it "can use as text prompt" do
      expect(described_class.new(**template).as_prompt(inputs: { you: :bob })).to eq({ prompt: "hi bob!" })
    end

    it "can use as chatGPT messases" do
      expect(described_class.new(**template).as_messages({ you: :bob })).to eq({ messages: [{ role: :assistant, content: "hi bob!" }] })
    end
  end
end
