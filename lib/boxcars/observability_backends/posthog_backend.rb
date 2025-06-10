# Ensure the base module is available
require_relative '../observability_backend'

module Boxcars
  # An observability backend for sending events to PostHog.
  #
  # This backend requires the `posthog-ruby` gem.
  # Add `gem 'posthog-ruby'` to your Gemfile to use this backend.
  #
  # Example Usage:
  #   require 'boxcars/observability_backends/posthog_backend'
  #   require 'posthog'
  #
  #   client = PostHog::Client.new(
  #     api_key: 'YOUR_POSTHOG_API_KEY',
  #     host: 'https://app.posthog.com' # or your self-hosted instance
  #   )
  #   Boxcars::Observability.backend = Boxcars::PosthogBackend.new(client: client)
  #
  #   # To track user-specific events, ensure :user_id is present in properties
  #   Boxcars::Observability.track(
  #     event: 'my_event',
  #     properties: { user_id: 'user_123', custom_data: 'value' }
  #   )
  class PosthogBackend
    include Boxcars::ObservabilityBackend

    # Initializes the PosthogBackend.
    # Accepts a pre-configured PostHog client instance.
    #
    # @param client [PostHog::Client] A configured PostHog client instance.
    # @raise [LoadError] if the 'posthog-ruby' gem is not available.
    def initialize(client:)
      begin
        require 'posthog'
      rescue LoadError
        raise LoadError, "The 'posthog-ruby' gem is required to use PosthogBackend. Please add it to your Gemfile."
      end

      @posthog_client = client
    end

    # Tracks an event with PostHog.
    #
    # The `:user_id` property is used as PostHog's `distinct_id`. If not provided,
    # events might be tracked anonymously or associated with a default/server ID
    # depending on PostHog's SDK behavior.
    #
    # All other properties are passed as event properties to PostHog.
    #
    # @param event [String, Symbol] The name of the event to track.
    # @param properties [Hash] A hash of properties for the event.
    #   It's recommended to include a `:user_id` for user-specific tracking.
    def track(event:, properties:)
      properties = {} unless properties.is_a?(Hash)
      distinct_id = properties.delete(:user_id) || current_user_id || "anonymous_user"
      @posthog_client.capture(distinct_id:, event:, properties:)
    end

    # Flushes any pending events to PostHog immediately.
    # This is useful for testing or when you need to ensure events are sent before the process exits.
    def flush
      @posthog_client.flush if @posthog_client.respond_to?(:flush)
    end

    # in Rails, this is a way to find the current user id
    def current_user_id
      return unless defined?(::Current) && ::Current.respond_to?(:user)

      ::Current.user&.id
    end
  end
end
