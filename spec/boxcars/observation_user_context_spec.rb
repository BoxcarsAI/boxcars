# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Boxcars::Observation do
  let(:user_context) do
    {
      id: 123,
      email: "test@example.com",
      role: "admin",
      name: "Test User"
    }
  end

  describe "user context functionality" do
    describe ".with_user" do
      it "creates an observation with user context" do
        observation = described_class.with_user(
          "Test note",
          user_context: user_context,
          status: :ok
        )

        expect(observation.note).to eq("Test note")
        expect(observation.status).to eq(:ok)
        expect(observation.user_context).to eq(user_context)
        expect(observation.user_context?).to be true
      end

      it "includes user context in added_context" do
        observation = described_class.with_user(
          "Test note",
          user_context: user_context,
          additional_data: "extra"
        )

        expect(observation.added_context[:user_context]).to eq(user_context)
        expect(observation.added_context[:additional_data]).to eq("extra")
      end
    end

    describe ".ok_with_user" do
      it "creates a successful observation with user context" do
        observation = described_class.ok_with_user(
          "Success message",
          user_context: user_context
        )

        expect(observation.status).to eq(:ok)
        expect(observation.user_context).to eq(user_context)
      end
    end

    describe ".err_with_user" do
      it "creates an error observation with user context" do
        observation = described_class.err_with_user(
          "Error message",
          user_context: user_context
        )

        expect(observation.status).to eq(:error)
        expect(observation.user_context).to eq(user_context)
      end
    end

    describe "#user_context" do
      it "returns user context when present" do
        observation = described_class.new(
          note: "Test",
          user_context: user_context
        )

        expect(observation.user_context).to eq(user_context)
      end

      it "returns nil when user context is not present" do
        observation = described_class.new(note: "Test")

        expect(observation.user_context).to be_nil
      end
    end

    describe "#user_context?" do
      it "returns true when user context is present" do
        observation = described_class.new(
          note: "Test",
          user_context: user_context
        )

        expect(observation.user_context?).to be true
      end

      it "returns false when user context is not present" do
        observation = described_class.new(note: "Test")

        expect(observation.user_context?).to be false
      end
    end

    describe "#to_h" do
      it "includes user context in the hash representation" do
        observation = described_class.with_user(
          "Test note",
          user_context: user_context,
          extra_data: "test"
        )

        hash = observation.to_h

        expect(hash[:note]).to eq("Test note")
        expect(hash[:status]).to eq(:ok)
        expect(hash[:user_context]).to eq(user_context)
        expect(hash[:extra_data]).to eq("test")
      end
    end

    describe "#to_json" do
      it "includes user context in the JSON representation" do
        observation = described_class.with_user(
          "Test note",
          user_context: user_context
        )

        json_data = JSON.parse(observation.to_json)

        expect(json_data["note"]).to eq("Test note")
        expect(json_data["status"]).to eq("ok")
        expect(json_data["user_context"]).to eq(user_context.transform_keys(&:to_s))
      end
    end
  end

  describe "backward compatibility" do
    it "maintains existing functionality for observations without user context" do
      observation = described_class.ok("Test message", extra: "data")

      expect(observation.note).to eq("Test message")
      expect(observation.status).to eq(:ok)
      expect(observation.added_context[:extra]).to eq("data")
      expect(observation.user_context?).to be false
    end

    it "works with existing .err method" do
      observation = described_class.err("Error message", error_code: 500)

      expect(observation.note).to eq("Error message")
      expect(observation.status).to eq(:error)
      expect(observation.added_context[:error_code]).to eq(500)
      expect(observation.user_context?).to be false
    end
  end
end
