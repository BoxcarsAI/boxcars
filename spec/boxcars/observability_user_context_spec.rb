# frozen_string_literal: true

require 'spec_helper'
require 'boxcars/observability_backends/posthog_backend'

RSpec.describe Boxcars::Observability do
  let(:mock_backend) { instance_spy(Boxcars::PosthogBackend) }
  let(:user_context) do
    {
      id: 123,
      email: "test@example.com",
      role: "admin",
      name: "Test User"
    }
  end

  before do
    allow(Boxcars.configuration).to receive(:observability_backend).and_return(mock_backend)
  end

  describe ".track with user context" do
    context "when observation has user context" do
      let(:observation) do
        Boxcars::Observation.with_user(
          "Test observation",
          user_context: user_context,
          extra_data: "test"
        )
      end

      it "merges user context into properties with $user_ prefix" do
        expected_properties = {
          test_property: "value",
          "$user_id" => 123,
          "$user_email" => "test@example.com",
          "$user_role" => "admin",
          "$user_name" => "Test User"
        }

        described_class.track(
          event: 'test_event',
          properties: { test_property: "value" },
          observation: observation
        )

        expect(mock_backend).to have_received(:track).with(
          event: 'test_event',
          properties: expected_properties
        )
      end

      it "preserves existing $user_ prefixed properties" do
        user_context_with_prefix = {
          "$user_custom" => "custom_value",
          id: 123
        }

        observation = Boxcars::Observation.with_user(
          "Test",
          user_context: user_context_with_prefix
        )

        expected_properties = {
          test_property: "value",
          "$user_custom" => "custom_value",
          "$user_id" => 123
        }

        described_class.track(
          event: 'test_event',
          properties: { test_property: "value" },
          observation: observation
        )

        expect(mock_backend).to have_received(:track).with(
          event: 'test_event',
          properties: expected_properties
        )
      end
    end

    context "when observation has no user context" do
      let(:observation) do
        Boxcars::Observation.ok("Test observation", extra_data: "test")
      end

      it "tracks without user context" do
        properties = { test_property: "value" }

        described_class.track(
          event: 'test_event',
          properties: properties,
          observation: observation
        )

        expect(mock_backend).to have_received(:track).with(
          event: 'test_event',
          properties: properties
        )
      end
    end

    context "when no observation is provided" do
      it "tracks without user context" do
        properties = { test_property: "value" }

        described_class.track(
          event: 'test_event',
          properties: properties
        )

        expect(mock_backend).to have_received(:track).with(
          event: 'test_event',
          properties: properties
        )
      end
    end
  end

  describe ".track_observation" do
    let(:observation) do
      Boxcars::Observation.with_user(
        "Test observation note",
        user_context: user_context,
        custom_data: "test_value",
        status: :ok
      )
    end

    it "tracks observation with all context and user data" do
      expected_properties = {
        observation_note: "Test observation note",
        observation_status: :ok,
        timestamp: kind_of(String),
        user_context: user_context,
        custom_data: "test_value",
        additional_prop: "additional_value",
        "$user_id" => 123,
        "$user_email" => "test@example.com",
        "$user_role" => "admin",
        "$user_name" => "Test User"
      }

      described_class.track_observation(
        observation,
        additional_prop: "additional_value"
      )

      expect(mock_backend).to have_received(:track).with(
        event: 'boxcar_observation',
        properties: expected_properties
      )
    end

    it "allows custom event name" do
      described_class.track_observation(
        observation,
        event: 'custom_event'
      )

      expect(mock_backend).to have_received(:track).with(
        event: 'custom_event',
        properties: hash_including(
          observation_note: "Test observation note",
          observation_status: :ok
        )
      )
    end

    context "with observation without user context" do
      let(:observation_without_user) do
        Boxcars::Observation.ok("Simple observation", extra: "data")
      end

      it "tracks without user properties" do
        expected_properties = {
          observation_note: "Simple observation",
          observation_status: :ok,
          timestamp: kind_of(String),
          extra: "data"
        }

        described_class.track_observation(observation_without_user)

        expect(mock_backend).to have_received(:track).with(
          event: 'boxcar_observation',
          properties: expected_properties
        )
      end
    end
  end

  describe "error handling" do
    it "silently handles backend errors during tracking" do
      observation = Boxcars::Observation.with_user(
        "Test",
        user_context: user_context
      )

      allow(mock_backend).to receive(:track).and_raise(StandardError.new("Backend error"))

      expect do
        described_class.track(
          event: 'test_event',
          properties: {},
          observation: observation
        )
      end.not_to raise_error
    end

    it "silently handles backend errors during observation tracking" do
      observation = Boxcars::Observation.with_user(
        "Test",
        user_context: user_context
      )

      allow(mock_backend).to receive(:track).and_raise(StandardError.new("Backend error"))

      expect do
        described_class.track_observation(observation)
      end.not_to raise_error
    end
  end

  describe "backward compatibility" do
    it "maintains existing track method signature" do
      properties = { test_property: "value" }

      # Call without observation parameter (existing usage)
      described_class.track(
        event: 'test_event',
        properties: properties
      )

      expect(mock_backend).to have_received(:track).with(
        event: 'test_event',
        properties: properties
      )
    end
  end

  describe "private methods" do
    describe "#merge_user_context" do
      it "handles non-hash user context gracefully" do
        properties = { existing: "prop" }

        # This tests the private method indirectly through track
        observation = Boxcars::Observation.new(
          note: "Test",
          user_context: "invalid_context"
        )

        described_class.track(
          event: 'test_event',
          properties: properties,
          observation: observation
        )

        expect(mock_backend).to have_received(:track).with(
          event: 'test_event',
          properties: properties
        )
      end
    end
  end
end
