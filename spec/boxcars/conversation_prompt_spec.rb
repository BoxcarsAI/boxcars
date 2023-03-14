# frozen_string_literal: true

RSpec.describe Boxcars::ConversationPrompt do
  let(:convo) { Boxcars::Conversation.new(lines: [[:user, "hi %<you>s!"]]) }
  let(:convo_with_roles) { Boxcars::Conversation.new(lines: [[:user, "hi %<you>s!"]], show_roles: true) }

  context "with a conversation" do
    it "can use as text prompt" do
      expect(described_class.new(conversation: convo).as_prompt({ you: :bob })).to eq({ prompt: "hi bob!" })
    end

    it "can use as text prompt with roles" do
      expect(described_class.new(conversation: convo_with_roles).as_prompt({ you: :bob })).to eq({ prompt: "user: hi bob!" })
    end

    it "can use as chatGPT messases" do
      expect(described_class.new(conversation: convo).as_messages({ you: :bob })).to eq({ messages: [{ role: :user, content: "hi bob!" }] })
    end
  end
end
