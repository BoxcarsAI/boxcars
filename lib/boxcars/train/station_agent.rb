# frozen_string_literal: true

module Boxcars
  # Agent abstraction that wraps ToolTrain with ergonomic DSL and agent-as-tool semantics.
  #
  # Provides agent-friendly vocabulary (`instructions`, `tools`, `model`) and proper
  # agent-as-tool nesting for multi-agent composition. When passed as a tool to another
  # agent, the outer agent sees a single `input` string parameter and receives the
  # inner agent's final answer as an observation.
  class StationAgent < ToolTrain
    attr_reader :instructions, :on_tool_call, :on_tool_result, :on_complete, :on_event, :handoffs

    DEFAULT_NAME = "Station Agent"
    DEFAULT_DESCRIPTION = "A helpful AI agent"

    # Boxcar that wraps a target agent for handoff semantics.
    # When the LLM calls this tool, ToolTrain exits its loop (return_direct: true)
    # and the caller can inspect @pending_handoff for the target agent.
    class HandoffBoxcar < Boxcar
      attr_reader :target_agent

      def initialize(target_agent)
        @target_agent = target_agent
        sanitized = target_agent.name.to_s.gsub(/[^\w-]+/, "_").gsub(/\A_+|_+\z/, "").downcase
        super(
          name: "handoff_to_#{sanitized}",
          description: "Hand off the conversation to #{target_agent.name}: #{target_agent.description}",
          return_direct: true,
          parameters: {
            reason: { type: :string, required: true, description: "Why this handoff is needed" }
          }
        )
      end

      def input_keys
        [:reason]
      end

      def call(inputs:)
        reason = inputs[:reason] || inputs["reason"] || "No reason given"
        { answer: Result.from_text("Handing off to #{target_agent.name}: #{reason}") }
      end
    end

    # @param instructions [String] System prompt text (required)
    # @param tools [Array<Boxcars::Boxcar>] Boxcar or StationAgent instances to use as tools
    # @param engine [Boxcars::Engine] Engine instance; takes priority over model
    # @param name [String] Agent name (also used to derive tool_call_name when nested)
    # @param description [String] Used as tool_spec description when nested as a tool
    # @param kwargs [Hash] Additional options forwarded to ToolTrain. Also accepts:
    #   - model: [String] Model string (e.g., "sonnet") resolved via Engines.engine
    #   - mcp_clients: [Array] MCP client instances; tools auto-discovered
    #   - on_tool_call: [Proc] Called before tool execution; return false to block
    #   - on_tool_result: [Proc] Called after tool execution (informational)
    #   - on_complete: [Proc] Called when agent finishes without a handoff
    #   - on_event: [Proc] Called with AgentEvent for each lifecycle event
    #   - handoffs: [Array<StationAgent>] Agents available as handoff targets
    def initialize(instructions:, tools: [], engine: nil, name: DEFAULT_NAME, description: DEFAULT_DESCRIPTION, **kwargs)
      @instructions = instructions

      model = kwargs.delete(:model)
      mcp_clients = kwargs.delete(:mcp_clients) || []
      @on_tool_call = kwargs.delete(:on_tool_call)
      @on_tool_result = kwargs.delete(:on_tool_result)
      @on_complete = kwargs.delete(:on_complete)
      @on_event = kwargs.delete(:on_event)
      handoff_agents = kwargs.delete(:handoffs) || []
      resolved_engine = engine || (model ? Boxcars::Engines.engine(model: model) : nil)

      combined_tools = Array(tools)
      Array(mcp_clients).each do |client|
        combined_tools.concat(Boxcars::MCP.boxcars_from_client(client))
      end

      prompt = build_prompt

      kwargs[:parameters] ||= {
        input: { type: :string, description: "The task or question for this agent", required: true }
      }

      super(boxcars: combined_tools, engine: resolved_engine, name: name, description: description,
            prompt: prompt, **kwargs)

      install_handoffs(handoff_agents)
    end

    def output_keys
      base = super
      base.include?(:handoff) ? base : base + [:handoff]
    end

    # Override ToolTrain#call to track handoffs, fire callbacks, and emit events.
    def call(inputs:)
      @pending_handoff = nil
      @current_iteration = 0
      @total_tool_calls = 0
      emit_event(:agent_start, input: inputs[:input], agent_name: name)
      result = super
      if @pending_handoff
        result[:handoff] = @pending_handoff
        emit_event(:handoff, from_agent: name, to_agent: @pending_handoff[:agent].name,
                             reason: @pending_handoff[:reason])
      else
        on_complete&.call(result)
        emit_event(:agent_complete, output: result[:output], iterations: @current_iteration,
                                    tool_calls_count: @total_tool_calls)
      end
      result
    end

    # Stream agent events during execution.
    # @param input [String] User input
    # @yield [AgentEvent] Each lifecycle event as it occurs
    # @return [ConductResult] When block given
    # @return [Enumerator<AgentEvent>] When no block given
    def run_stream(input, &block)
      if block
        previous_on_event = @on_event
        @on_event = block
        conduct(input)
      else
        Enumerator.new { |y| run_stream(input) { |event| y << event } }
      end
    ensure
      @on_event = previous_on_event if block
    end

    # No template placeholders beyond %<input>s, so no extra variables needed.
    def prediction_additional(_inputs)
      {}
    end

    private

    # Emit an event to the on_event callback, swallowing errors.
    def emit_event(type, **data)
      return unless on_event

      event = AgentEvent.new(type: type, data: data, iteration: @current_iteration || 0)
      on_event.call(event)
    rescue StandardError => e
      Boxcars.error("Error in on_event callback: #{e.message}", :red)
    end

    # Override ToolTrain#tool_call_response to emit LLM call events.
    def tool_call_response(messages, tools, responses_state: nil)
      @current_iteration = (@current_iteration || 0) + 1
      emit_event(:llm_call_start, iteration: @current_iteration, message_count: messages.length)
      response = super
      emit_event(:llm_response, iteration: @current_iteration)
      response
    end

    # Override ToolTrain#execute_tool_call to add lifecycle callbacks, handoff detection, and events.
    def execute_tool_call(tool_call)
      function_payload = tool_call[:function] || {}
      tool_name = function_payload[:name].to_s
      raw_arguments = function_payload[:arguments].to_s
      boxcar = tool_call_name_to_boxcar[tool_name]

      # Parse args for callback (best-effort)
      parsed_args = begin
        boxcar ? parse_tool_arguments(raw_arguments, boxcar) : {}
      rescue StandardError
        {}
      end

      # on_tool_call guardrail: return false to block execution
      if on_tool_call && boxcar
        guard_result = on_tool_call.call(tool_name, parsed_args)
        if guard_result == false
          emit_event(:tool_call_blocked, tool_name: tool_name, args: parsed_args)
          tool_call_id = tool_call[:id]
          action = TrainAction.new(boxcar: tool_name, boxcar_input: parsed_args, log: "Blocked by on_tool_call guard")
          observation = Observation.err("Tool call to #{tool_name} was blocked by guardrail.")
          tool_message = { role: :tool, tool_call_id: tool_call_id, content: observation.to_text }
          return [action, observation, tool_message, false]
        end
      end

      emit_event(:tool_call_start, tool_name: tool_name, args: parsed_args)

      # Detect handoff before delegating to super
      if boxcar.is_a?(HandoffBoxcar)
        reason = parsed_args[:reason] || parsed_args["reason"] || "No reason given"
        @pending_handoff = { agent: boxcar.target_agent, reason: reason }
      end

      # Delegate to ToolTrain for actual execution
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      action, observation, tool_message, return_direct = super
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

      @total_tool_calls = (@total_tool_calls || 0) + 1

      # on_tool_result callback (informational)
      on_tool_result&.call(tool_name, parsed_args, observation)

      status = observation.status == :ok ? :success : :error
      emit_event(:tool_call_end, tool_name: tool_name, duration_ms: duration_ms, status: status)

      [action, observation, tool_message, return_direct]
    end

    def install_handoffs(handoff_agents)
      @handoffs = Array(handoff_agents)
      @handoffs.each do |agent|
        handoff_boxcar = HandoffBoxcar.new(agent)
        @boxcars << handoff_boxcar
        @name_to_boxcar_map[handoff_boxcar.name] = handoff_boxcar
        @tool_call_name_to_boxcar = nil # invalidate cache
      end
    end

    def build_prompt
      lines = [
        Boxcar.syst(instructions),
        Boxcar.hist,
        Boxcar.user("%<input>s")
      ]
      conversation = Conversation.new(lines: lines)
      ConversationPrompt.new(
        conversation: conversation,
        input_variables: [:input],
        output_variables: [:answer]
      )
    end
  end
end
