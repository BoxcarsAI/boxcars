module Boxcars
  # Module to be included by observability backend implementations.
  # It defines the interface that all backends must adhere to.
  module ObservabilityBackend
    # Tracks an event with associated properties.
    # This method must be implemented by any class that includes this module.
    #
    # @param event [String, Symbol] The name of the event being tracked (e.g., :llm_call, :train_run).
    # @param properties [Hash] A hash of properties associated with the event.
    #   Common properties might include :user_id, :prompt, :response, :model_name,
    #   :duration_ms, :success, :error_message, etc.
    # @raise [NotImplementedError] if the including class does not implement this method.
    def track(event:, properties:)
      raise NotImplementedError, "#{self.class.name} must implement the `track` method."
    end
  end
end
