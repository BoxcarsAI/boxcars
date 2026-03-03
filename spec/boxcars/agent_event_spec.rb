# frozen_string_literal: true

require "spec_helper"

RSpec.describe Boxcars::AgentEvent do
  describe "initialization" do
    it "accepts valid event types" do
      Boxcars::AgentEvent::TYPES.each do |type|
        event = described_class.new(type: type)
        expect(event.type).to eq(type)
      end
    end

    it "raises ArgumentError for unknown types" do
      expect { described_class.new(type: :bogus) }.to raise_error(ArgumentError, /Unknown event type/)
    end

    it "freezes data on init" do
      event = described_class.new(type: :agent_start, data: { foo: "bar" })
      expect(event.data).to be_frozen
      expect(event.data).to eq({ foo: "bar" })
    end

    it "sets timestamp" do
      event = described_class.new(type: :agent_start)
      expect(event.timestamp).to be_a(Time)
      expect(event.timestamp).to be_within(1).of(Time.now)
    end

    it "stores iteration" do
      event = described_class.new(type: :llm_call_start, iteration: 3)
      expect(event.iteration).to eq(3)
    end

    it "defaults iteration to 0" do
      event = described_class.new(type: :agent_start)
      expect(event.iteration).to eq(0)
    end

    it "defaults data to empty hash" do
      event = described_class.new(type: :agent_start)
      expect(event.data).to eq({})
    end
  end
end
