# frozen_string_literal: true

require 'spec_helper'
require 'boxcars/observability_backends/multi_backend'
require 'boxcars/observability_backend' # For dummy backends

RSpec.describe Boxcars::MultiBackend do
  let(:dummy_backend_one) do
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

  let(:dummy_backend_two) do
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
      # rubocop: disable Lint/UnusedMethodArgument
      def track(event:, properties:)
        raise StandardError, "This backend intentionally fails."
      end
      # rubocop: enable Lint/UnusedMethodArgument
    end.new
  end

  describe '#initialize' do
    it 'initializes with an array of backends' do
      backends = [dummy_backend_one, dummy_backend_two]
      multi_backend = described_class.new(backends)
      expect(multi_backend.instance_variable_get(:@backends)).to eq(backends)
    end

    it 'compacts nil backends from the array' do
      backends = [dummy_backend_one, nil, dummy_backend_two]
      multi_backend = described_class.new(backends)
      expect(multi_backend.instance_variable_get(:@backends)).to eq([dummy_backend_one, dummy_backend_two])
    end

    it 'raises ArgumentError if any backend does not implement :track' do
      invalid_backend = Class.new.new # Does not include ObservabilityBackend
      backends = [dummy_backend_one, invalid_backend]
      expect do
        described_class.new(backends)
      end.to raise_error(Boxcars::ArgumentError, /All backends must implement the `track` method/)
    end

    it 'accepts a single backend' do
      multi_backend = described_class.new(dummy_backend_one)
      expect(multi_backend.instance_variable_get(:@backends)).to eq([dummy_backend_one])
    end

    it 'initializes with an empty array if nil is passed' do
      multi_backend = described_class.new(nil)
      expect(multi_backend.instance_variable_get(:@backends)).to eq([])
    end
  end

  describe '#track' do
    let(:event_name) { :multi_event }
    let(:event_properties) { { data: 'value', id: 123 } }

    context 'with multiple successful backends' do
      let(:multi_backend) { described_class.new([dummy_backend_one, dummy_backend_two]) }

      it 'calls track on each backend' do
        multi_backend.track(event: event_name, properties: event_properties)

        expect(dummy_backend_one.tracked_events.size).to eq(1)
        expect(dummy_backend_one.tracked_events.first[:event]).to eq(event_name)
        expect(dummy_backend_one.tracked_events.first[:properties]).to eq(event_properties)

        expect(dummy_backend_two.tracked_events.size).to eq(1)
        expect(dummy_backend_two.tracked_events.first[:event]).to eq(event_name)
        expect(dummy_backend_two.tracked_events.first[:properties]).to eq(event_properties)
      end

      it 'passes a duplicated properties hash to each backend' do
        allow(event_properties).to receive(:dup).and_call_original.twice # Expect dup to be called for each backend

        multi_backend.track(event: event_name, properties: event_properties)

        expect(event_properties).to have_received(:dup).twice
        # Verify properties are not mutated (original test for this is tricky without more complex backend mocks)
        # This test mainly ensures `dup` is called.
      end
    end

    context 'when one backend fails' do
      let(:multi_backend) { described_class.new([dummy_backend_one, failing_backend, dummy_backend_two]) }

      it 'calls track on all backends and does not propagate the error' do
        expect do
          multi_backend.track(event: event_name, properties: event_properties)
        end.not_to raise_error

        expect(dummy_backend_one.tracked_events.size).to eq(1)
        expect(dummy_backend_two.tracked_events.size).to eq(1)
      end
    end

    context 'with no backends' do
      let(:multi_backend) { described_class.new([]) }

      it 'does nothing and does not raise an error' do
        expect do
          multi_backend.track(event: event_name, properties: event_properties)
        end.not_to raise_error
      end
    end
  end
end
