# frozen_string_literal: true

module Boxcars
  # used by Boxcars to return structured result and additional context
  class Observation
    attr_reader :note, :status, :added_context

    # @param note [String] The note to use for the result
    # @param status [Symbol] :ok or :error
    # @param added_context [Hash] Any additional context to add to the result
    def initialize(note:, status: :ok, **added_context)
      @note = note
      @status = status
      @added_context = added_context
    end

    # @return [Hash] The result as a hash
    def to_h
      {
        note: note,
        status: status,
      }.merge(added_context).compact
    end

    # @return [String] The result as a json string
    def to_json(*args)
      JSON.generate(to_h, *args)
    end

    # @return [String] An explanation of the result
    def to_s
      note
    end

    # create a new Observaton from a text string with a status of :ok
    # @param note [String] The text to use for the observation
    # @param added_context [Hash] Any additional context to add to the result
    # @return [Boxcars::Observation] The observation
    def self.ok(note, **kwargs)
      new(note: note, status: :ok, **kwargs)
    end

    # create a new Observaton from a text string with a status of :error
    # @param note [String] The text to use for the observation
    # @param added_context [Hash] Any additional context to add to the result
    # @return [Boxcars::Observation] The observation
    def self.err(note, **kwargs)
      new(note: note, status: :error, **kwargs)
    end
  end
end
