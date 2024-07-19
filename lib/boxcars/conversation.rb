# frozen_string_literal: true

module Boxcars
  # used to keep track of the conversation
  class Conversation
    attr_reader :lines

    PEOPLE = %i[system user assistant history].freeze

    def initialize(lines: [])
      @lines = lines
      check_lines(@lines)
    end

    # check the lines
    def check_lines(lines)
      raise ArgumentError, "Lines must be an array" unless lines.is_a?(Array)

      lines.each do |ln|
        raise ArgumentError, "Conversation item must be a array" unless ln.is_a?(Array)
        raise ArgumentError, "Conversation item must have 2 items, role and text" unless ln.size == 2
        raise ArgumentError, "Conversation item must have a role #{ln} in (#{PEOPLE})" unless PEOPLE.include? ln[0]
      end
    end

    # @return [Array] The result as a convesation array
    def to_a
      lines
    end

    # @return [String] A conversation string
    def to_s
      lines.map { |ln| "#{ln[0]}: #{ln[1]}" }.join("\n")
    end

    # add assistant text to the conversation at the end
    # @param text [String] The text to add
    def add_assistant(text)
      @lines << [:assistant, text]
    end

    # add user text to the conversation at the end
    # @param text [String] The text to add
    def add_user(text)
      @lines << [:user, text]
    end

    # add system text to the conversation at the end
    # @param text [String] The text to add
    def add_system(text)
      @lines << [:system, text]
    end

    # add multiple lines to the conversation
    def add_lines(lines)
      check_lines(lines)
      @lines += lines
    end

    # add a conversation to the conversation
    def add_conversation(conversation)
      @lines += conversation.lines
    end

    # insert converation above history line if it is present
    # @param conversation [Conversation] The conversation to add
    def add_history(conversation)
      # find the history line
      hi = lines.rindex { |ln| ln[0] == :history }
      return unless hi

      @lines = @lines.dup

      # insert the conversation above the history line
      @lines.insert(hi, *conversation.lines)
    end

    def no_history
      @lines.reject { |ln| ln[0] == :history }
    end

    # return just the messages for the conversation
    def message_text
      lines.map(&:last).join("\n")
    end

    # compute the prompt parameters with input substitutions (used for chatGPT)
    # @param inputs [Hash] The inputs to use for the prompt.
    # @return [Hash] The formatted prompt { messages: ...}
    def as_messages(inputs = nil)
      { messages: no_history.map { |ln| { role: ln.first, content: cformat(ln.last, inputs) } } }
    rescue ::KeyError => e
      first_line = e.message.to_s.split("\n").first
      Boxcars.error "Missing prompt input key: #{first_line}"
      raise KeyError, "Prompt format error: #{first_line}"
    end

    # compute the prompt parameters with input substitutions
    # @param inputs [Hash] The inputs to use for the prompt.
    # @return [Hash] The formatted prompt { prompt: "..."}
    def as_prompt(inputs: nil, prefixes: default_prefixes, show_roles: false)
      if show_roles
        lines = no_history.map { |ln| [prefixes[ln[0]], ln[1]] }
        lines.map { |ln| cformat("#{ln.first}#{ln.last}", inputs) }.compact.join("\n\n")
      else
        no_history.map { |ln| cformat(ln.last, inputs) }.compact.join("\n\n")
      end
    rescue ::KeyError => e
      first_line = e.message.to_s.split("\n").first
      Boxcars.error "Missing prompt input key: #{first_line}"
      raise KeyError, "Prompt format error: #{first_line}"
    end

    def process_content(content, inputs)
      # If content is a string, treat it as text
      if content.is_a?(String)
        [{ type: "text", text: cformat(content, inputs) }]
      # If content is an array, assume it's already in the new format
      elsif content.is_a?(Array)
        content.map do |item|
          if item[:type] == "text"
            { type: "text", text: cformat(item[:text], inputs) }
          else
            item # Pass through non-text items (like images) without modification
          end
        end
      else
        raise ArgumentError, "Invalid content type: #{content.class}"
      end
    end

    # special format that replaces lone percent signs with double percent signs
    def cformat(*args)
      args[0] = args[0].dup.gsub(/%(?!<)/, '%%') if args.length > 1
      format(*args)
    end

    def default_prefixes
      { system: 'System: ', user: 'User: ', assistant: 'Assistant: ', history: :history }
    end
  end
end
