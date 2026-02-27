# frozen_string_literal: true

module Boxcars
  # used by Boxcars to return structured result and additional context
  class Result
    attr_accessor :status, :answer, :explanation, :suggestions, :added_context

    # @param status [Symbol] :ok or :error
    # @param answer [String] The answer to the question
    # @param explanation [String] The explanation of the answer
    # @param suggestions [Array<String>] The next suggestions for the user
    # @param added_context [Hash] Any additional context to add to the result
    def initialize(status:, answer: nil, explanation: nil, suggestions: nil, **added_context)
      @status = status
      @answer = answer || explanation
      @explanation = explanation
      @suggestions = suggestions
      @added_context = added_context
    end

    # @return [Hash] The result as a hash
    def to_h
      { status:, answer:, explanation:, suggestions: }.merge(added_context).compact
    end

    # @return [String] The result as a json string
    def to_json(*)
      JSON.generate(to_h, *)
    end

    # @return [String] An explanation of the result
    def to_s
      explanation
    end

    # @return [String] The answer data to the question
    def to_answer
      answer
    end

    # @return [Boolean] True when result status is `:ok`.
    def ok?
      status == :ok
    end

    # @return [Boolean] True when result status is `:error`.
    def error?
      status == :error
    end

    # create a new Result from a text string
    # @param text [String] The text to use for the result
    # @param kwargs [Hash] Any additional kwargs to pass to the result
    # @return [Boxcars::Result] The result
    def self.from_text(text, **)
      str = text.to_s
      answer = str.delete_prefix('"').delete_suffix('"').strip
      answer = Regexp.last_match(:answer) if answer =~ /^Answer:\s*(?<answer>.*)$/
      explanation = "Answer: #{answer}"
      new(status: :ok, answer:, explanation:, **)
    end

    # create a new Result from an error string
    # @param error [String] The error to use for the result
    # @param kwargs [Hash] Any additional kwargs to pass to the result
    # @return [Boxcars::Result] The error result
    def self.from_error(error, **)
      answer = error
      answer = Regexp.last_match(:answer) if answer =~ /^Error:\s*(?<answer>.*)$/
      explanation = "Error: #{answer}"
      new(status: :error, answer:, explanation:, **)
    end

    # Extract a Boxcars::Result from common boxcar return values.
    # @param value [Object] Usually a `Boxcar#conduct` hash or a `Boxcars::Result`.
    # @return [Boxcars::Result,nil] Extracted result when present.
    def self.extract(value)
      return value if value.is_a?(Result)
      if value.respond_to?(:answer_result)
        candidate = value.answer_result
        return candidate if candidate.is_a?(Result)
      end
      return nil unless value.is_a?(Hash)

      candidate = value[:answer] || value["answer"]
      candidate if candidate.is_a?(Result)
    end

    # Validate that a value is a conduct-style payload containing a `Boxcars::Result`.
    # @param value [Object] Usually a `Boxcar#conduct` hash.
    # @return [Boolean] True when a `Boxcars::Result` can be extracted.
    def self.valid_conduct_payload?(value)
      !extract(value).nil?
    end
  end
end
