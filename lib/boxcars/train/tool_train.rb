# frozen_string_literal: true

require "json"

module Boxcars
  # A Train runtime that uses native LLM tool-calling instead of text ReAct parsing.
  class ToolTrain < Train
    attr_accessor :wants_next_actions

    # Lightweight prompt wrapper so engine adapters can send an exact message list.
    class MessagePrompt < Prompt
      def initialize(messages)
        @messages = messages
        super(template: "")
      end

      def as_messages(_inputs = nil)
        { messages: @messages }
      end

      def as_prompt(inputs: nil, **)
        { prompt: @messages.map { |m| "#{m[:role]}: #{message_content(m)}" }.join("\n") }
      end

      private

      def message_content(message)
        content = message[:content]
        return content if content.is_a?(String)

        content.to_json
      rescue StandardError
        content.to_s
      end
    end

    DEFAULT_NAME = "Tool Calling Train"
    DEFAULT_DESCRIPTION = "Train that uses native tool-calling when supported by the engine."

    CTEMPLATE = [
      syst(
        "Answer the user's question using the provided tools when helpful.\n",
        "If a tool is needed, call it with valid arguments.\n",
        "If no tool is needed, answer directly.\n",
        "Available tools:\n",
        "%<boxcar_descriptions>s\n",
        "%<next_actions>s"
      ),
      hist,
      user("%<input>s")
    ].freeze

    def initialize(boxcars:, engine: nil, name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, prompt: nil, **kwargs)
      @wants_next_actions = kwargs.fetch(:wants_next_actions, false)
      prompt ||= my_prompt
      super(boxcars:, engine:, prompt:, name:, description:, **kwargs)
    end

    def prediction_additional(_inputs)
      { boxcar_descriptions:, next_actions: }.merge(super)
    end

    # Tool-calling runtime loop; does not use text parsing.
    def call(inputs:)
      prepare_for_new_call
      ensure_tool_calling_engine!

      conversation_messages = initial_messages(inputs)
      tool_specs = boxcars.map(&:tool_spec)
      intermediate_steps = []
      iterations = 0
      responses_state = responses_runtime? ? { previous_response_id: nil, response_input: nil } : nil

      while should_continue?(iterations)
        response = normalize_response_payload(tool_call_response(conversation_messages, tool_specs, responses_state:))
        assistant_message = extract_assistant_message(response)
        conversation_messages << assistant_message

        tool_calls = assistant_message[:tool_calls]
        if tool_calls.is_a?(Array) && !tool_calls.empty?
          response_tool_outputs = []
          tool_calls.each do |tool_call|
            action, observation, tool_message, return_direct = execute_tool_call(tool_call)
            intermediate_steps << [action, observation]
            Boxcars.debug "Observation: #{observation}", :green

            return pre_return(TrainFinish.new({ return_values[0] => observation }, log: ""), intermediate_steps) if return_direct

            conversation_messages << tool_message
            response_tool_outputs << responses_tool_output_item(tool_call, observation) if responses_state
          end

          if responses_state
            responses_state[:previous_response_id] = response[:id]
            responses_state[:response_input] = response_tool_outputs
          end

          iterations += 1
          next
        end

        responses_state[:response_input] = nil if responses_state

        final_text = extract_assistant_text(assistant_message)
        output = TrainFinish.new({ output: final_text }, log: final_text)
        return pre_return(output, intermediate_steps)
      end

      pre_return(TrainFinish.new({ output: "Agent stopped due to max iterations." }, log: ""), intermediate_steps)
    end

    private

    def ensure_tool_calling_engine!
      return if engine.respond_to?(:supports?) && engine.supports?(:tool_calling)

      raise Boxcars::ArgumentError, "#{engine.class} does not support native tool-calling"
    end

    def initial_messages(inputs)
      prompt_inputs = prediction_additional(inputs).merge(inputs)
      raw_messages = prompt.as_messages(prompt_inputs).fetch(:messages)
      raw_messages.map { |msg| normalize_message(msg) }
    end

    def tool_call_response(messages, tools, responses_state: nil)
      # `tool_choice: "auto"` works for OpenAI-compatible chat APIs.
      kwargs = {
        tools: tools,
        tool_choice: "auto"
      }
      prompt_messages = messages

      if responses_state && responses_state[:response_input]
        kwargs[:response_input] = responses_state[:response_input]
        kwargs[:previous_response_id] = responses_state[:previous_response_id] if responses_state[:previous_response_id]
        prompt_messages = []
      end

      engine.client(
        prompt: MessagePrompt.new(prompt_messages),
        inputs: {},
        **kwargs
      )
    end

    def extract_assistant_message(response)
      if responses_api_response?(response)
        return extract_responses_assistant_message(response)
      end

      message = response.dig(:choices, 0, :message)
      raise Boxcars::Error, "Tool-calling response missing assistant message" unless message.is_a?(Hash)

      normalize_message(message)
    end

    def responses_api_response?(response)
      response.is_a?(Hash) && response[:output].is_a?(Array)
    end

    def extract_responses_assistant_message(response)
      output_items = response[:output] || []
      tool_calls = []
      text_parts = []

      output_items.each do |item|
        next unless item.is_a?(Hash)

        type = item[:type].to_s
        case type
        when "function_call"
          tool_calls << {
            id: item[:id] || item[:call_id],
            type: "function",
            _responses_call_id: item[:call_id],
            function: {
              name: item[:name],
              arguments: item[:arguments] || "{}"
            }
          }
        when "message"
          content = item[:content]
          if content.is_a?(Array)
            content.each do |part|
              next unless part.is_a?(Hash)

              part_type = part[:type].to_s
              next unless %w[output_text text].include?(part_type)

              text_val = part[:text]
              if text_val.is_a?(String)
                text_parts << text_val
              elsif text_val.is_a?(Hash)
                text_parts << (text_val[:value] || text_val[:text]).to_s
              end
            end
          end
        when "output_text"
          text_parts << (item[:text] || item[:content]).to_s
        end
      end

      output_text = response[:output_text]
      if output_text.is_a?(String)
        text_parts.unshift(output_text)
      elsif output_text.is_a?(Array)
        output_text.each do |entry|
          if entry.is_a?(String)
            text_parts << entry
          elsif entry.is_a?(Hash)
            text_parts << (entry[:value] || entry[:text] || entry[:content]).to_s
          end
        end
      end

      {
        role: :assistant,
        content: text_parts.map(&:to_s).map(&:strip).reject(&:empty?).join("\n"),
        tool_calls: tool_calls
      }
    end

    def normalize_message(message)
      normalized = {}
      message.each do |key, value|
        normalized[key.to_sym] = normalize_message_value(value)
      end
      normalized[:role] ||= :assistant
      normalized[:role] = normalized[:role].to_sym if normalized[:role].is_a?(String)
      normalized
    end

    def normalize_message_value(value)
      case value
      when Hash
        value.each_with_object({}) do |(k, v), out|
          out[k.to_sym] = normalize_message_value(v)
        end
      when Array
        value.map { |v| normalize_message_value(v) }
      else
        value
      end
    end

    def execute_tool_call(tool_call)
      tool_call_id = tool_call[:id]
      function_payload = tool_call[:function] || {}
      tool_name = function_payload[:name].to_s
      raw_arguments = function_payload[:arguments].to_s
      boxcar = tool_call_name_to_boxcar[tool_name]

      unless boxcar
        action = TrainAction.new(boxcar: :error, boxcar_input: nil, log: "Unknown tool call: #{tool_name}")
        observation = Observation.err("Error - #{tool_name} is not a valid tool, try again.")
        tool_message = { role: :tool, tool_call_id:, content: observation.to_text }
        return [action, observation, tool_message, false]
      end

      action_input = parse_tool_arguments(raw_arguments, boxcar)
      action = TrainAction.new(boxcar: boxcar.name, boxcar_input: action_input, log: tool_call_log(tool_call, action_input))

      begin
        result = get_boxcar_result(boxcar, action_input)
        observation = Observation.ok(result)
        return_direct = boxcar.return_direct
      rescue Boxcars::ConfigurationError, Boxcars::SecurityError => e
        raise e
      rescue StandardError => e
        Boxcars.error "Error in #{boxcar.name} tool call: #{e}", :red
        observation = Observation.err("Error - #{e}, correct and try again.")
        return_direct = false
      end

      tool_message = {
        role: :tool,
        tool_call_id: tool_call_id,
        content: serialize_observation_for_llm(observation)
      }
      [action, observation, tool_message, return_direct]
    end

    def responses_tool_output_item(tool_call, observation)
      {
        type: "function_call_output",
        call_id: tool_call[:_responses_call_id] || tool_call[:id],
        output: serialize_observation_for_llm(observation)
      }
    end

    def tool_call_log(tool_call, action_input)
      fn = tool_call[:function] || {}
      "Tool Call: #{fn[:name]} #{action_input.inspect}"
    end

    def parse_tool_arguments(raw_arguments, boxcar)
      return default_tool_arguments_for(boxcar) if raw_arguments.strip.empty?

      parsed = JSON.parse(raw_arguments)
      case parsed
      when Hash
        parsed.transform_keys { |k| k.to_sym rescue k }
      else
        if boxcar.input_keys.length == 1
          { boxcar.input_keys.first => parsed }
        else
          raise Boxcars::ArgumentError, "Tool arguments for #{boxcar.name} must be an object"
        end
      end
    rescue JSON::ParserError => e
      raise Boxcars::ArgumentError, "Invalid JSON arguments for #{boxcar.name}: #{e.message}"
    end

    def default_tool_arguments_for(boxcar)
      return {} if boxcar.input_keys.empty?

      if boxcar.input_keys.length == 1
        { boxcar.input_keys.first => "" }
      else
        {}
      end
    end

    def serialize_observation_for_llm(observation)
      note = observation.note
      case note
      when Result
        note.to_json
      when Hash, Array
        JSON.generate(note)
      else
        observation.to_text
      end
    rescue StandardError
      observation.to_text
    end

    def extract_assistant_text(message)
      content = message[:content]

      if content.is_a?(String)
        return content
      elsif content.is_a?(Array)
        text = content.filter_map do |part|
          next unless part.is_a?(Hash)

          if part[:text].is_a?(String)
            part[:text]
          elsif part[:type].to_s.include?("text") && part[:text].is_a?(Hash)
            part[:text][:value] || part[:text][:text]
          end
        end.join("\n").strip
        return text unless text.empty?
      end

      "No final answer returned."
    end

    def normalize_response_payload(response)
      return response unless response.is_a?(Hash)

      normalize_message_value(response)
    end

    def tool_call_name_to_boxcar
      @tool_call_name_to_boxcar ||= boxcars.to_h { |boxcar| [boxcar.tool_call_name, boxcar] }
    end

    def responses_runtime?
      engine.respond_to?(:supports?) && engine.supports?(:responses_api)
    end

    def my_prompt
      @conversation ||= Conversation.new(lines: CTEMPLATE)
      @my_prompt ||= ConversationPrompt.new(
        conversation: @conversation,
        input_variables: [:input],
        other_inputs: [:boxcar_descriptions, :next_actions],
        output_variables: [:answer]
      )
    end
  end

  # Backwards-compatible alias for the initial v0.10 naming.
  ToolCallingTrain = ToolTrain
end
