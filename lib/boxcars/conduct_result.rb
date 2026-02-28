# frozen_string_literal: true

module Boxcars
  # Hash-like result wrapper returned by `Boxcar#conduct`.
  # Supports legacy `result[:answer].answer` access while guiding users toward
  # `Boxcars::Result.extract(result)`.
  class ConductResult < Hash
    LEGACY_ANSWER_ACCESS_REMOVE_IN = "3.0"
    @emit_legacy_answer_access_warnings = true
    @warned_legacy_answer_access = false

    class << self
      attr_accessor :emit_legacy_answer_access_warnings

      def reset_deprecation_warnings!
        @warned_legacy_answer_access = false
      end
    end

    # @param hash [Hash] Initial result payload.
    def initialize(hash = {})
      super()
      update(hash)
    end

    def [](key)
      warn_legacy_answer_access(key)
      super
    end

    def fetch(key, *args, &block)
      warn_legacy_answer_access(key)
      super
    end

    # Extract `Boxcars::Result` from conduct payload without triggering the
    # legacy `[:answer]` deprecation warning.
    # @return [Boxcars::Result,nil]
    def answer_result
      candidate =
        if key?(:answer)
          hash_read(:answer)
        elsif key?("answer")
          hash_read("answer")
        end
      candidate if candidate.is_a?(Boxcars::Result)
    end

    private

    def warn_legacy_answer_access(key)
      return unless key == :answer || key == "answer"
      return unless self.class.emit_legacy_answer_access_warnings
      return unless Boxcars.configuration.emit_deprecation_warnings
      return if self.class.instance_variable_get(:@warned_legacy_answer_access)

      Boxcars.warn("Deprecated conduct hash access `result[:answer].answer`; use `Boxcars::Result.extract(result)&.answer` (planned removal in v#{LEGACY_ANSWER_ACCESS_REMOVE_IN})")
      self.class.instance_variable_set(:@warned_legacy_answer_access, true)
    end

    def hash_read(key)
      Hash.instance_method(:[]).bind_call(self, key)
    end
  end
end
