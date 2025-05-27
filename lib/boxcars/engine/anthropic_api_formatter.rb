# frozen_string_literal: true

require_relative 'anthropic_message_combiner'

module Boxcars
  # Module to handle formatting for Anthropic API requests
  module AnthropicApiFormatter
    include AnthropicMessageCombiner

    # convert generic parameters to Anthropic specific ones
    def convert_to_anthropic(params)
      params[:messages] ||= [] # Ensure :messages is an array
      _map_anthropic_specific_params(params)
      _handle_anthropic_system_prompt(params)
      _format_all_message_contents(params)
      _pop_empty_last_message(params)
      combine_assistant(params) # Now uses AnthropicMessageCombiner
    end

    private

    def _format_all_message_contents(params)
      params[:messages].each do |message|
        next unless message.is_a?(Hash) && message.key?(:content)

        message[:content] = _anthropic_format_message_content(message[:content])
      end
    end

    def _pop_empty_last_message(params)
      return unless params[:messages].is_a?(Array) && !params[:messages].empty?

      last_message = params[:messages].last
      if last_message.is_a?(Hash) && last_message[:content]&.blank?
        params[:messages].pop
      elsif !last_message.is_a?(Hash)
        Boxcars.logger&.warn "Last message is not a Hash: #{last_message.inspect}"
      end
    end

    # Ensures message content is in a format Anthropic accepts (string or array of content blocks)
    def _anthropic_format_message_content(content)
      return content if content.is_a?(String)
      return content if content.is_a?(Array) && content.all? { |item| item.is_a?(Hash) && item.key?(:type) }

      # If it's an array of strings or other things, try to convert to text blocks
      return content.map { |item| _convert_item_to_text_block(item) } if content.is_a?(Array)

      # Default fallback for other types
      [{ type: "text", text: content.to_s }]
    end

    def _convert_item_to_text_block(item)
      if item.is_a?(String)
        { type: "text", text: item }
      elsif item.is_a?(Hash) && item.key?(:text) # Simple hash with text
        { type: "text", text: item[:text] }
      else
        { type: "text", text: item.to_s } # Fallback
      end
    end

    def _handle_anthropic_system_prompt(params)
      first_message = params[:messages].first
      return unless first_message.is_a?(Hash) && first_message[:role]&.to_s == 'system'

      system_message = params[:messages].shift
      if system_message.key?(:content)
        params[:system] = _anthropic_extract_message_content_from_parts(system_message[:content])
      else
        Boxcars.logger&.warn "System message lacks :content key: #{system_message.inspect}"
        params[:system] = ""
      end
    end

    def _anthropic_extract_message_content_from_parts(message_content)
      return message_content if message_content.is_a?(String)

      if message_content.is_a?(Array)
        return message_content.map do |part|
          part.is_a?(Hash) ? part[:text] || part.to_s : part.to_s
        end.join("\n")
      end

      message_content.to_s
    end

    def _map_anthropic_specific_params(params)
      if params.key?(:max_tokens) && !params.key?(:max_tokens_to_sample)
        params[:max_tokens_to_sample] = params.delete(:max_tokens)
      end
      params.delete(:max_tokens) if params.key?(:max_tokens_to_sample)
      params[:stop_sequences] = params.delete(:stop) if params.key?(:stop)
    end
  end
end
