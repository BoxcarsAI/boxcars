# frozen_string_literal: true

require 'spec_helper'
require 'boxcars/observability'
require 'boxcars/observability_backend' # Needed for the dummy backend

RSpec.describe Boxcars::Observability do
  let(:dummy_backend) do
    Class.new do
      include Boxcars::ObservabilityBackend
      attr_reader :tracked_events

      def initialize
        @tracked_events = []
      end

      def track(event:, properties:)
        @tracked_events << { event: event, properties: properties }
      end
    end.new
  end

  let(:failing_backend) do
    Class.new do
      include Boxcars::ObservabilityBackend
      def track(event:, properties:)
        Rails.logger.debug "Dummy backend: #{event} with properties: #{properties}"
        raise StandardError, "Backend failed!"
      end
    end.new
  end

  before do
    # Reset backend before each test
    described_class.backend = nil
  end

  after do
    # Ensure backend is reset after tests if it was set
    described_class.backend = nil
  end

  describe '.backend' do
    it 'can have a backend assigned' do
      described_class.backend = dummy_backend
      expect(described_class.backend).to eq(dummy_backend)
    end

    it 'is nil by default' do
      expect(described_class.backend).to be_nil
    end
  end

  describe '.track' do
    context 'when a backend is configured' do
      before do
        described_class.backend = dummy_backend
      end

      it 'calls track on the configured backend with event and properties' do
        event_name = :test_event
        event_properties = { foo: 'bar', count: 1 }

        described_class.track(event: event_name, properties: event_properties)

        expect(dummy_backend.tracked_events.size).to eq(1)
        tracked_call = dummy_backend.tracked_events.first
        expect(tracked_call[:event]).to eq(event_name)
        expect(tracked_call[:properties]).to eq(event_properties)
      end

      it 'does not raise an error if the backend raises an error (fails silently)' do
        described_class.backend = failing_backend
        event_name = :failing_event
        event_properties = { detail: 'this will fail' }

        expect do
          described_class.track(event: event_name, properties: event_properties)
        end.not_to raise_error
      end

      it 'does not call track if properties is not a Hash (though current impl allows it, good to test behavior)' do
        # The current implementation of Observability.track doesn't validate properties type,
        # it's the backend's responsibility. This test confirms it passes through.
        event_name = :test_event
        event_properties = "not a hash"

        # We expect the dummy_backend to receive it as is.
        # If dummy_backend had stricter checks, this test would need adjustment or the dummy_backend would raise.
        expect { described_class.track(event: event_name, properties: event_properties) }.not_to raise_error
        expect(dummy_backend.tracked_events.first[:properties]).to eq("not a hash")
      end
    end

    context 'when no backend is configured' do
      it 'does not raise an error and does nothing' do
        expect(described_class.backend).to be_nil
        expect do
          described_class.track(event: :some_event, properties: { data: 'value' })
        end.not_to raise_error
      end
    end
  end
end
