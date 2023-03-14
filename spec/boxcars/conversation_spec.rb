# frozen_string_literal: true

RSpec.describe Boxcars::Conversation do
  context "when error conditions" do
    it "confirms proper array format" do
      expect do
        described_class.new(lines: nil)
      end.to raise_error(Boxcars::ArgumentError)
    end

    it "validates line must be an array" do
      expect do
        described_class.new(lines: [:user])
      end.to raise_error(Boxcars::ArgumentError)
    end

    it "validates the size of line" do
      expect do
        described_class.new(lines: [[:user, "123"], ["abc"]])
      end.to raise_error(Boxcars::ArgumentError)
    end

    it "validates role of lines" do
      expect do
        described_class.new(lines: [[:user, "123"], [:foo, "abc"]])
      end.to raise_error(Boxcars::ArgumentError)
    end

    it "validates conversation is a string" do
      expect do
        described_class.new(lines: [[:user, { a: 1 }]])
      end.to raise_error(Boxcars::ArgumentError)
    end
  end

  context "with valid arguments" do
    it "can make a prompt" do
      expect(described_class.new(lines: [[:user, "foo"]]).as_prompt).to eq("foo")
    end

    it "can make a prompt with role" do
      expect(described_class.new(lines: [[:user, "foo"]], show_roles: true).as_prompt).to eq("user: foo")
    end

    it "can make a converstation" do
      expect(described_class.new(lines: [[:user, "foo"]], show_roles: true).as_messages).to eq({ messages: [{ role: :user, content: "foo" }] })
    end
  end
end
