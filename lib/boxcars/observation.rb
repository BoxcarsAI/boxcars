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
        note:,
        status:
      }.merge(added_context).compact
    end

    # @return [String] The result as a json string
    def to_json(*)
      JSON.generate(to_h, *)
    end

    # @return [String] An explanation of the result
    def to_s
      note.to_s
    end

    # @return [String] An explanation of the result
    def to_text
      to_s
    end

    # create a new Observaton from a text string with a status of :ok
    # @param note [String] The text to use for the observation
    # @param added_context [Hash] Any additional context to add to the result
    # @return [Boxcars::Observation] The observation
    def self.ok(note, **)
      new(note:, status: :ok, **)
    end

    # create a new Observaton from a text string with a status of :error
    # @param note [String] The text to use for the observation
    # @param added_context [Hash] Any additional context to add to the result
    # @return [Boxcars::Observation] The observation
    def self.err(note, **)
      new(note:, status: :error, **)
    end

    # create a new Observation with user context
    # @param note [String] The text to use for the observation
    # @param user_context [Hash] User information (e.g., { id: 123, email: "user@example.com", role: "admin" })
    # @param status [Symbol] :ok or :error
    # @param added_context [Hash] Any additional context to add to the result
    # @return [Boxcars::Observation] The observation
    def self.with_user(note, user_context:, status: :ok, **)
      new(note:, status:, user_context:, **)
    end

    # create a new Observation with user context and status :ok
    # @param note [String] The text to use for the observation
    # @param user_context [Hash] User information (e.g., { id: 123, email: "user@example.com", role: "admin" })
    # @param added_context [Hash] Any additional context to add to the result
    # @return [Boxcars::Observation] The observation
    def self.ok_with_user(note, user_context:, **)
      with_user(note, user_context:, status: :ok, **)
    end

    # create a new Observation with user context and status :error
    # @param note [String] The text to use for the observation
    # @param user_context [Hash] User information (e.g., { id: 123, email: "user@example.com", role: "admin" })
    # @param added_context [Hash] Any additional context to add to the result
    # @return [Boxcars::Observation] The observation
    def self.err_with_user(note, user_context:, **)
      with_user(note, user_context:, status: :error, **)
    end

    # Extract user context from the observation
    # @return [Hash, nil] The user context if present
    def user_context
      added_context[:user_context]
    end

    # Check if this observation has user context
    # @return [Boolean] true if user context is present
    def user_context?
      !user_context.nil?
    end
  end
end
