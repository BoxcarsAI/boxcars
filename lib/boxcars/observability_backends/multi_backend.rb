# Ensure the base module is available.
# This might be handled by autoloading in a Rails app,
# but explicit require is safer for gems.
require_relative '../observability_backend'

module Boxcars
  # An observability backend that delegates tracking calls to multiple other backends.
  # This allows sending observability data to several destinations simultaneously.
  class MultiBackend
    include Boxcars::ObservabilityBackend

    # Initializes a new MultiBackend.
    #
    # @param backends [Array<ObservabilityBackend>] An array of backend instances.
    #   Each instance must include {Boxcars::ObservabilityBackend}.
    def initialize(backends)
      @backends = Array(backends).compact # Ensure it's an array and remove nils
      return if @backends.all? { |b| b.respond_to?(:track) }

      raise ArgumentError, "All backends must implement the `track` method (i.e., include Boxcars::ObservabilityBackend)."
    end

    # Tracks an event by calling `track` on each configured backend.
    # It passes a duplicated `properties` hash to each backend to prevent
    # unintended modifications if one backend alters the hash.
    # Errors from individual backends are silently ignored to ensure
    # other backends still receive the event.
    #
    # @param event [String, Symbol] The name of the event to track.
    # @param properties [Hash] A hash of properties associated with the event.
    def track(event:, properties:)
      @backends.each do |backend_instance|
        # Pass a duplicated properties hash to prevent mutation issues across backends
        backend_instance.track(event:, properties: properties.dup)
      rescue StandardError
        # Silently ignore errors from individual backends.
        # Optionally, log:
        # Boxcars.logger.warn "Boxcars::MultiBackend: Error in backend #{backend_instance.class.name}: #{e.message}"
      end
    end
  end
end
