# frozen_string_literal: true

require "spec_helper"

RSpec.describe Boxcars::Result do
  describe ".extract" do
    let(:result) { described_class.new(status: :ok, answer: "hello") }

    it "returns the same value for a direct result instance" do
      expect(described_class.extract(result)).to eq(result)
    end

    it "extracts result from a conduct-style hash with symbol key" do
      expect(described_class.extract({ answer: result })).to eq(result)
    end

    it "extracts result from a conduct-style hash with string key" do
      expect(described_class.extract({ "answer" => result })).to eq(result)
    end

    it "returns nil when :answer is present but not a Boxcars::Result" do
      expect(described_class.extract({ answer: "hello" })).to be_nil
    end

    it "returns nil for non-hash, non-result values" do
      expect(described_class.extract("hello")).to be_nil
    end

    it "extracts from ConductResult without triggering legacy hash access warnings" do
      Boxcars::ConductResult.reset_deprecation_warnings!
      allow(Boxcars).to receive(:warn)

      conduct_result = Boxcars::ConductResult.new(answer: result, input: "hello")
      expect(described_class.extract(conduct_result)).to eq(result)
      expect(Boxcars).not_to have_received(:warn)
    end
  end

  describe ".valid_conduct_payload?" do
    let(:result) { described_class.new(status: :ok, answer: "hello") }

    it "returns true when a conduct payload contains a Boxcars::Result" do
      expect(described_class.valid_conduct_payload?({ answer: result })).to be(true)
    end

    it "returns false when a conduct payload does not contain a Boxcars::Result" do
      expect(described_class.valid_conduct_payload?({ answer: "hello" })).to be(false)
    end
  end

  describe "#ok? and #error?" do
    it "reports ok status" do
      expect(described_class.new(status: :ok).ok?).to be(true)
      expect(described_class.new(status: :ok).error?).to be(false)
    end

    it "reports error status" do
      expect(described_class.new(status: :error).error?).to be(true)
      expect(described_class.new(status: :error).ok?).to be(false)
    end
  end
end
