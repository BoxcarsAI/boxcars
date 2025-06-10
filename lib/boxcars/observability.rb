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
      # @param observation [Boxcars::Observation, nil] Optional observation object to extract user context from.
      def track(event:, properties:, observation: nil)
        return unless backend

        # Merge user context from observation if present
        final_properties = properties.dup
        final_properties = merge_user_context(final_properties, observation.user_context) if observation&.user_context?

        backend.track(event:, properties: final_properties)
      rescue StandardError
        # Fail silently as requested.
        # Optionally, if Boxcars had a central logger:
        # Boxcars.logger.warn "Boxcars::Observability: Backend error during track: #{e.message} (#{e.class.name})"
      end

      # Tracks an observation event, automatically extracting user context if present
      # @param observation [Boxcars::Observation] The observation to track
      # @param event [String, Symbol] The event name (defaults to 'boxcar_observation')
      # @param additional_properties [Hash] Additional properties to include
      def track_observation(observation, event: 'boxcar_observation', **additional_properties)
        properties = {
          observation_note: observation.note,
          observation_status: observation.status,
          timestamp: Time.now.iso8601
        }.merge(additional_properties)

        # Add all observation context (including user_context) to properties
        properties.merge!(observation.added_context) if observation.added_context

        track(event:, properties:, observation:)
      end

      private

      # Merge user context into properties with proper namespacing
      # @param properties [Hash] The existing properties
      # @param user_context [Hash] The user context to merge
      # @return [Hash] The merged properties
      def merge_user_context(properties, user_context)
        return properties unless user_context.is_a?(Hash)

        # Add user context with proper prefixing for analytics systems
        user_properties = {}
        user_context.each do |key, value|
          # Use $user_ prefix for PostHog compatibility
          user_key = key.to_s.start_with?('$user_') ? key : "$user_#{key}"
          user_properties[user_key] = value
        end

        properties.merge(user_properties)
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
