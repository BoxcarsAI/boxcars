# frozen_string_literal: true

module Boxcars
  # Module to handle combining Anthropic assistant messages
  module AnthropicMessageCombiner
    # Public method, intended to be part of AnthropicApiFormatter's API if it was public there
    def combine_assistant(params)
      params[:messages] = combine_assistant_entries(params[:messages])
      _rstrip_last_assistant_message_content(params[:messages])
      params
    end

    # Public method, intended to be part of AnthropicApiFormatter's API if it was public there
    def combine_assistant_entries(hashes)
      return [] if hashes.nil? || hashes.empty?

      combined_hashes = []
      hashes.each_with_index do |hash, index|
        unless hash.is_a?(Hash) && hash.key?(:role) && hash.key?(:content)
          Boxcars.logger&.warn "Skipping malformed message entry at index #{index}: #{hash.inspect}"
          next
        end

        current_role = hash[:role]&.to_s

        if _should_merge_with_previous_assistant_entry?(current_role, index, combined_hashes)
          # Merge with the previous assistant entry
          combined_hashes.last[:content] = _merge_consecutive_assistant_contents(
            combined_hashes.last[:content],
            hash[:content]
          )
        else
          # Append new entry
          combined_hashes << hash.dup
        end
      end
      combined_hashes
    end

    private

    def _rstrip_last_assistant_message_content(messages)
      last_message = messages.last
      # Ensure last_message is a Hash before using dig with a symbol
      return unless last_message.is_a?(Hash) && last_message[:role]&.to_s == 'assistant'

      # last_message is now confirmed to be a Hash
      content = last_message[:content]
      if content.is_a?(Array)
        content.each do |part|
          part[:text]&.rstrip! if part.is_a?(Hash) && part[:type] == "text"
        end
      elsif content.is_a?(String)
        last_message[:content].rstrip!
      end
    end

    def _merge_consecutive_assistant_contents(last_content, current_content)
      # Ensure contents are arrays of blocks for merging
      last_content_blocks = last_content.is_a?(String) ? [{ type: "text", text: last_content }] : Array(last_content)
      current_content_blocks = current_content.is_a?(String) ? [{ type: "text", text: current_content }] : Array(current_content)

      last_content_blocks.concat(current_content_blocks)
    end

    def _should_merge_with_previous_assistant_entry?(current_role, current_index, combined_entries)
      return false unless current_role == 'assistant'
      return false unless current_index.positive?
      return false unless combined_entries.last&.dig(:role)&.to_s == 'assistant'

      true
    end
  end
end
