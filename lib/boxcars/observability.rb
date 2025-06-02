module Boxcars
  # Provides a central point for tracking observability events.
  # It allows configuring a backend (or multiple backends via MultiBackend)
  # to which events and their properties will be sent.
  class Observability
    class << self
      # @!attribute [r] backend
      #   @return [ObservabilityBackend, nil] The configured observability backend.
      #     This should be an object that includes the {Boxcars::ObservabilityBackend} module.
      #     It can be a single backend instance or an instance of {Boxcars::MultiBackend}.
      #     If `nil`, tracking calls will be no-ops.
      #     The backend is retrieved from Boxcars.configuration.observability_backend.
      def backend
        Boxcars.configuration.observability_backend
      end

      # Tracks an event if a backend is configured.
      # This method will silently ignore errors raised by the backend's `track` method
      # to prevent observability issues from disrupting the main application flow.
      #
      # @param event [String, Symbol] The name of the event to track.
      # @param properties [Hash] A hash of properties associated with the event.
      def track(event:, properties:)
        return unless backend

        backend.track(event: event, properties: properties)
      rescue StandardError
        # Fail silently as requested.
        # Optionally, if Boxcars had a central logger:
        # Boxcars.logger.warn "Boxcars::Observability: Backend error during track: #{e.message} (#{e.class.name})"
      end

      # Flushes any pending events if the backend supports it.
      # This is useful for testing or when you need to ensure events are sent before the process exits.
      def flush
        return unless backend

        backend.flush if backend.respond_to?(:flush)
      rescue StandardError
        # Fail silently as requested.
      end
    end
  end
end
