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
  #   Boxcars::Observability.backend = Boxcars::PosthogBackend.new(
  #     api_key: 'YOUR_POSTHOG_API_KEY',
  #     host: 'https://app.posthog.com' # or your self-hosted instance
  #   )
  #
  #   # To track user-specific events, ensure :user_id is present in properties
  #   Boxcars::Observability.track(
  #     event: 'my_event',
  #     properties: { user_id: 'user_123', custom_data: 'value' }
  #   )
  class PosthogBackend
    include Boxcars::ObservabilityBackend

    # Initializes the PosthogBackend.
    # Configures the PostHog client with the provided API key and host.
    #
    # @param api_key [String] Your PostHog project API key.
    # @param host [String] The PostHog API host. Defaults to 'https://app.posthog.com'.
    # @param _personal_api_key [String, nil] Optional: A personal API key for server-side operations if needed.
    # @param on_error [Proc, nil] Optional: A lambda/proc to call when an error occurs during event capture.
    #   It receives the error code and error body as arguments.
    #   Defaults to a proc that logs the error to stderr.
    # @raise [LoadError] if the 'posthog-ruby' gem is not available.
    def initialize(api_key:, host: 'https://app.posthog.com', _personal_api_key: nil, on_error: nil)
      begin
        require 'posthog'
      rescue LoadError
        raise LoadError, "The 'posthog-ruby' gem is required to use PosthogBackend. Please add it to your Gemfile."
      end

      @on_error_proc = on_error || proc do |status, body|
        Boxcars.error("PostHog error: Status #{status}, Body: #{body}", :red)
      end

      # The posthog-ruby gem uses a simpler API
      @posthog_client = PostHog::Client.new(
        api_key: api_key,
        host: host,
        on_error: @on_error_proc
      )
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
      # Ensure properties is a hash, duplicate to avoid mutation by PostHog or other backends
      tracking_properties = properties.is_a?(Hash) ? properties.dup : {}

      distinct_id = tracking_properties.delete(:user_id) || tracking_properties.delete('user_id')

      # If no distinct_id is found, provide a default value since PostHog requires it
      distinct_id ||= "anonymous_user"

      # The PostHog gem's capture method handles distinct_id and properties.
      # It's important that distinct_id is a string.
      @posthog_client.capture(
        distinct_id: distinct_id.to_s, # Ensure distinct_id is a string
        event: event.to_s, # Ensure event name is a string
        properties: tracking_properties
      )
      # The posthog-ruby client handles flushing events asynchronously.
      # If immediate flushing is needed for testing or specific scenarios:
      # @posthog_client.flush
    end
  end
end
