# Boxcars Agents Guide

This guide covers `Boxcars::StationAgent`, `AgentRunner`, and `AgentEvent` — the multi-agent system built on top of `ToolTrain`.

## Overview

For the core framework concepts (Engines, Boxcars, Trains, MCP), see the [Boxcars Guide](./boxcars_guide.md).

`StationAgent` is a higher-level abstraction over `ToolTrain` that adds:

- **Agent-friendly DSL** — `instructions:`, `tools:`, `model:` instead of raw prompt/boxcar/engine wiring
- **Agent-as-tool nesting** — pass one agent as a tool to another for multi-agent composition
- **Lifecycle callbacks** — `on_tool_call`, `on_tool_result`, `on_complete` for guardrails and observability
- **Handoffs** — agents can transfer conversations to other agents
- **Event streaming** — real-time lifecycle events via `on_event` and `run_stream`

**When to use `StationAgent` vs raw `ToolTrain`:**

| Use `StationAgent` when you need... | Use `ToolTrain` when you need... |
|---|---|
| Multi-agent composition (nesting, handoffs) | A single tool-calling loop without agent semantics |
| Lifecycle callbacks or event streaming | Maximum control over prompt construction |
| Clean DSL for instructions/tools/model | Custom prompt templates with multiple variables |

## Quick Start

### Minimal Agent (Direct Answer)

An agent with no tools answers directly from its LLM:

```ruby
require "boxcars"

agent = Boxcars::StationAgent.new(
  instructions: "You are a friendly greeting bot.",
  model: "sonnet"
)
puts agent.run("Hello!")
# => "Hello! How can I help you today?"
```

### Agent with Tools

Add tools to let the agent call them during its reasoning loop:

```ruby
calc = Boxcars::Calculator.new
search = Boxcars::GoogleSearch.new

agent = Boxcars::StationAgent.new(
  instructions: "You are a research assistant. Use tools to find and compute answers.",
  tools: [calc, search],
  model: "gpt-4o"
)
puts agent.run("What is pi times the population of Tokyo?")
```

### Engine vs Model

You can specify the LLM two ways:

```ruby
# Short form: model string (resolved via Boxcars::Engines.engine)
agent = Boxcars::StationAgent.new(instructions: "Hello", model: "sonnet")

# Long form: engine instance (full control)
engine = Boxcars::Anthropic.new(model: "claude-sonnet-4-20250514", max_tokens: 4096)
agent = Boxcars::StationAgent.new(instructions: "Hello", engine: engine)
```

When neither `model:` nor `engine:` is given, the default engine (`Boxcars.engine`) is used.

## Tools

### Using Built-in Boxcar Tools

Any `Boxcars::Boxcar` subclass works as a tool:

```ruby
agent = Boxcars::StationAgent.new(
  instructions: "You help with math and data lookups.",
  tools: [
    Boxcars::Calculator.new,
    Boxcars::GoogleSearch.new,
    Boxcars::WikipediaSearch.new
  ],
  model: "gpt-4o"
)
```

### Using MCP Tools

Connect MCP servers and their tools are auto-discovered:

```ruby
mcp_client = Boxcars::MCP.stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"])

begin
  agent = Boxcars::StationAgent.new(
    instructions: "You can read and write files.",
    mcp_clients: [mcp_client],
    model: "gpt-4o"
  )
  puts agent.run("List files in /tmp")
ensure
  mcp_client.close
end
```

### Mixing Local and MCP Tools

```ruby
mcp_client = Boxcars::MCP.stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"])

begin
  agent = Boxcars::StationAgent.new(
    instructions: "You can do math and manage files.",
    tools: [Boxcars::Calculator.new],
    mcp_clients: [mcp_client],
    model: "gpt-4o"
  )
  puts agent.run("What is 2+2 and what files are in /tmp?")
ensure
  mcp_client.close
end
```

## Agent-as-Tool Nesting

### Passing One Agent as a Tool to Another

When you pass a `StationAgent` as an element of the `tools:` array, the outer agent sees it as a single-input tool. The outer agent sends a string, the inner agent runs to completion, and the outer agent receives the final answer as an observation.

```ruby
engine = Boxcars::Engines.engine(model: "gpt-4o")

researcher = Boxcars::StationAgent.new(
  instructions: "You are a research specialist. Use Google to find accurate information.",
  tools: [Boxcars::GoogleSearch.new],
  engine: engine,
  name: "Researcher",
  description: "Researches topics using web search"
)

writer = Boxcars::StationAgent.new(
  instructions: "You write clear, concise summaries. Use the Researcher for facts you don't know.",
  tools: [researcher],
  engine: engine,
  name: "Writer",
  description: "Writes summaries"
)

puts writer.run("Write a 3-sentence summary of the Ruby 3.4 release")
```

### How tool_spec / tool_call_name Work

When nested as a tool, `StationAgent` exposes:

- **`tool_call_name`** — derived from the agent's `name:`, sanitized for LLM tool-calling (e.g., `"Research Bot"` becomes `"Research_Bot"`)
- **`tool_spec`** — a function with a single `input` string parameter
- **`description`** — the agent's `description:` (not its `instructions:`, which stay private)

```ruby
agent = Boxcars::StationAgent.new(
  instructions: "Secret internal prompt.",
  name: "Research Bot",
  description: "Answers research questions",
  engine: engine
)

agent.tool_call_name  # => "Research_Bot"
agent.tool_spec
# => { type: "function", function: { name: "Research_Bot",
#      description: "Answers research questions",
#      parameters: { "type" => "object",
#        "properties" => { "input" => { "type" => "string", ... } }, ... } } }
```

### Full Example: Dispatcher + Specialists

```ruby
engine = Boxcars::Engines.engine(model: "gpt-4o")

math_agent = Boxcars::StationAgent.new(
  instructions: "You solve math problems step by step.",
  tools: [Boxcars::Calculator.new],
  engine: engine,
  name: "Math Specialist",
  description: "Solves math problems"
)

search_agent = Boxcars::StationAgent.new(
  instructions: "You answer factual questions using web search.",
  tools: [Boxcars::GoogleSearch.new],
  engine: engine,
  name: "Search Specialist",
  description: "Answers factual questions via web search"
)

dispatcher = Boxcars::StationAgent.new(
  instructions: "You are a dispatcher. Route questions to the right specialist tool.",
  tools: [math_agent, search_agent],
  engine: engine
)

puts dispatcher.run("What is the square root of the GDP of France in billions?")
```

## Lifecycle Callbacks

### on_tool_call (Guardrail)

Called **before** each tool execution with `(tool_name, args)`. Return `false` to block the call — the LLM will see a "blocked by guardrail" message and can adjust.

```ruby
agent = Boxcars::StationAgent.new(
  instructions: "You are a data assistant.",
  tools: [Boxcars::SQLActiveRecord.new(models: [User, Order])],
  engine: engine,
  on_tool_call: lambda { |tool_name, args|
    # Block any tool call that looks like it modifies data
    if args.to_s.match?(/DELETE|DROP|UPDATE/i)
      puts "BLOCKED: #{tool_name} attempted a write operation"
      return false
    end
    true
  }
)
```

Any return value other than `false` (including `nil` and `true`) allows the tool call to proceed.

### on_tool_result (Post-Execution Observation)

Called **after** each tool execution with `(tool_name, args, observation)`. This is informational — you cannot modify the observation.

```ruby
agent = Boxcars::StationAgent.new(
  instructions: "You are a helpful assistant.",
  tools: [Boxcars::Calculator.new],
  engine: engine,
  on_tool_result: lambda { |tool_name, args, observation|
    puts "[#{tool_name}] args=#{args.inspect} status=#{observation.status}"
  }
)
```

### on_complete (Terminal Callback)

Called when the agent finishes **without** a handoff. Not called when the agent hands off to another agent.

```ruby
agent = Boxcars::StationAgent.new(
  instructions: "You are a helpful assistant.",
  engine: engine,
  on_complete: lambda { |result|
    puts "Agent completed with output keys: #{result.keys}"
  }
)
```

### Callback Ordering

For a typical tool-calling flow, callbacks fire in this order:

1. `on_tool_call` (before execution — can block)
2. Tool executes (or is blocked)
3. `on_tool_result` (after execution — informational)
4. _(repeat for more tool calls)_
5. `on_complete` (once agent produces a final answer)

Callback errors are caught and logged — they never break the agent loop.

## Handoffs

### What Handoffs Are

A handoff lets one agent transfer the conversation to another agent. This is useful for triage/routing patterns where a front-line agent decides which specialist should handle the request.

### Setting Up Handoff Targets

Pass agents to the `handoffs:` parameter. Each becomes a tool named `handoff_to_<agent_name>`:

```ruby
billing = Boxcars::StationAgent.new(
  instructions: "You handle billing questions.",
  engine: engine,
  name: "Billing Agent",
  description: "Handles billing and payment questions"
)

support = Boxcars::StationAgent.new(
  instructions: "You handle technical support.",
  engine: engine,
  name: "Support Agent",
  description: "Handles technical issues"
)

router = Boxcars::StationAgent.new(
  instructions: "You are a triage agent. Route the user to the right specialist.",
  engine: engine,
  handoffs: [billing, support]
)
```

The router agent sees two tools: `handoff_to_billing_agent` and `handoff_to_support_agent`. Each takes a `reason` parameter.

### How HandoffBoxcar Works

Internally, each handoff target is wrapped in a `StationAgent::HandoffBoxcar` with `return_direct: true`. When the LLM calls the handoff tool, the agent loop exits immediately and the result includes a `:handoff` key with the target agent and reason.

### Inspecting Handoff Results

Use `conduct` (not `run`) to inspect the raw result including handoff data:

```ruby
result = router.conduct("I need a refund")

if (handoff = result.output_for(:handoff))
  puts "Handing off to: #{handoff[:agent].name}"
  puts "Reason: #{handoff[:reason]}"
  # Now run the target agent
  answer = handoff[:agent].run("I need a refund")
end
```

## AgentRunner

### Following Handoff Chains Automatically

`AgentRunner` automates the handoff pattern — it runs the starting agent, follows any handoff, and repeats until an agent completes without a handoff:

```ruby
billing = Boxcars::StationAgent.new(
  instructions: "Handle billing questions.", engine: engine,
  name: "Billing Agent", description: "Handles billing"
)

refund = Boxcars::StationAgent.new(
  instructions: "Process refund requests.", engine: engine,
  name: "Refund Agent", description: "Processes refunds"
)

# Billing can hand off to Refund
billing_with_handoffs = Boxcars::StationAgent.new(
  instructions: "Handle billing. If user wants a refund, hand off to the Refund Agent.",
  engine: engine, name: "Billing Agent", description: "Handles billing",
  handoffs: [refund]
)

router = Boxcars::StationAgent.new(
  instructions: "Route user requests to the right department.",
  engine: engine, handoffs: [billing_with_handoffs]
)

runner = Boxcars::AgentRunner.new(starting_agent: router, max_handoffs: 5)
result = runner.run("I want a refund on my last order")

puts result[:answer]
# => "Your refund has been processed..."

puts result[:handoff_chain]
# => [
#      { from: "Station Agent", to: "Billing Agent", reason: "billing question" },
#      { from: "Billing Agent", to: "Refund Agent", reason: "needs refund" }
#    ]
```

### max_handoffs Safety Limit

The `max_handoffs` parameter (default: 10) prevents infinite handoff loops. When the limit is hit, the runner returns a message explaining why it stopped:

```ruby
runner = Boxcars::AgentRunner.new(starting_agent: router, max_handoffs: 3)
result = runner.run("Help me")

# If the chain exceeds 3 handoffs:
result[:answer]  # => "Agent stopped due to max handoffs (3)."
```

### Extracting Answers and Handoff Chains

The result hash always contains:

- **`:answer`** — the final agent's text answer (String)
- **`:handoff_chain`** — array of `{ from:, to:, reason: }` hashes, empty if no handoffs occurred

## Event Streaming

### on_event Constructor Callback

Pass `on_event:` to receive `AgentEvent` instances during execution:

```ruby
agent = Boxcars::StationAgent.new(
  instructions: "You are helpful.",
  tools: [Boxcars::Calculator.new],
  engine: engine,
  on_event: lambda { |event|
    puts "[#{event.type}] iter=#{event.iteration} #{event.data}"
  }
)
agent.run("What is 42 * 17?")
```

### run_stream with Block

Returns the `ConductResult` after yielding each event:

```ruby
result = agent.run_stream("What is 42 * 17?") do |event|
  case event.type
  when :tool_call_start
    puts "Calling #{event.data[:tool_name]}..."
  when :tool_call_end
    puts "Done in #{event.data[:duration_ms]}ms (#{event.data[:status]})"
  when :agent_complete
    puts "Finished after #{event.data[:iterations]} iterations"
  end
end
```

### run_stream without Block

Returns a lazy `Enumerator` — useful for streaming to clients or piping to other processing:

```ruby
stream = agent.run_stream("What is 42 * 17?")

stream.each do |event|
  puts event.type
end
```

### All Event Types

| Event Type | Data Keys | Description |
|---|---|---|
| `agent_start` | `input`, `agent_name` | Agent begins execution |
| `llm_call_start` | `iteration`, `message_count` | LLM API call begins |
| `llm_response` | `iteration` | LLM API call returns |
| `tool_call_start` | `tool_name`, `args` | Tool execution begins |
| `tool_call_blocked` | `tool_name`, `args` | `on_tool_call` returned `false` |
| `tool_call_end` | `tool_name`, `duration_ms`, `status` | Tool execution completed (`:success` or `:error`) |
| `handoff` | `from_agent`, `to_agent`, `reason` | Agent is handing off |
| `agent_complete` | `output`, `iterations`, `tool_calls_count` | Agent finished (no handoff) |
| `agent_error` | _(varies)_ | Agent encountered an error |

Every event also carries:
- `event.type` — the Symbol type
- `event.data` — frozen Hash with the data keys above
- `event.timestamp` — `Time` when the event was created
- `event.iteration` — current agent loop iteration (Integer)

### AgentRunner#run_stream for Multi-Agent Events

`AgentRunner` also supports `run_stream`, yielding events from every agent in the handoff chain:

```ruby
runner = Boxcars::AgentRunner.new(starting_agent: router, max_handoffs: 5)

result = runner.run_stream("I want a refund") do |event|
  puts "[#{event.type}] #{event.data}"
end

# Events come from each agent as the chain executes
# You'll see agent_start for the router, then handoff, then agent_start for billing, etc.
```

Without a block, returns an `Enumerator`:

```ruby
stream = runner.run_stream("I want a refund")
stream.each { |event| puts event.type }
```

### Error Resilience

Callback errors (in `on_event`, `on_tool_call`, `on_tool_result`, `on_complete`) are caught and logged — they never break the agent loop. This makes it safe to use event callbacks for non-critical purposes like logging and metrics.

```ruby
agent = Boxcars::StationAgent.new(
  instructions: "You are helpful.",
  engine: engine,
  on_event: ->(_event) { raise "logging infrastructure is down" }
)

# Agent still runs and returns an answer despite the callback error
agent.run("Hello")  # => works fine
```

## Choosing an Engine

### model: Shorthand vs engine: Instance

```ruby
# model: string — resolved via Boxcars::Engines.engine(model:)
agent = Boxcars::StationAgent.new(instructions: "Hello", model: "sonnet")
agent = Boxcars::StationAgent.new(instructions: "Hello", model: "gpt-4o")
agent = Boxcars::StationAgent.new(instructions: "Hello", model: "gemini-2.5-flash")

# engine: instance — full control over engine configuration
engine = Boxcars::Anthropic.new(model: "claude-sonnet-4-20250514", max_tokens: 8192)
agent = Boxcars::StationAgent.new(instructions: "Hello", engine: engine)
```

### Engine Factory Aliases

See the [Engine Factory section in the Boxcars Guide](./boxcars_guide.md#engine-factory-boxcarsengines) for the full list of supported model aliases. Common ones for agents:

- `"sonnet"` — Claude Sonnet (Anthropic)
- `"opus"` — Claude Opus (Anthropic)
- `"gpt-4o"` — GPT-4o (OpenAI)
- `"gpt-5-mini"` — GPT-5 Mini (OpenAI)
- `"gemini-2.5-flash"` — Gemini Flash (Google)
- `"sonar"` — Sonar (Perplexity)

## Patterns & Recipes

### Triage Router Pattern

A router agent dispatches to specialist agents based on the user's request:

```ruby
engine = Boxcars::Engines.engine(model: "gpt-4o")

billing = Boxcars::StationAgent.new(
  instructions: "You handle billing and payment questions. Be helpful and specific.",
  engine: engine, name: "Billing Agent", description: "Handles billing questions"
)

support = Boxcars::StationAgent.new(
  instructions: "You handle technical support. Ask for error messages and logs.",
  engine: engine, name: "Support Agent", description: "Handles technical issues"
)

sales = Boxcars::StationAgent.new(
  instructions: "You handle sales inquiries. Be enthusiastic but not pushy.",
  engine: engine, name: "Sales Agent", description: "Handles sales and pricing questions"
)

router = Boxcars::StationAgent.new(
  instructions: <<~INSTRUCTIONS,
    You are a triage agent. Based on the user's message, hand off to the most
    appropriate specialist. If the request doesn't fit any specialist, answer directly.
  INSTRUCTIONS
  engine: engine,
  handoffs: [billing, support, sales]
)

runner = Boxcars::AgentRunner.new(starting_agent: router)
result = runner.run("How much does the enterprise plan cost?")
# => Routes to Sales Agent, which answers the pricing question
```

### Guardrail Agent

Use `on_tool_call` to enforce safety policies:

```ruby
BLOCKED_TOOLS = %w[dangerous_operation drop_table].freeze

agent = Boxcars::StationAgent.new(
  instructions: "You are a database assistant.",
  tools: [Boxcars::SQLActiveRecord.new(models: [User, Order])],
  engine: engine,
  on_tool_call: lambda { |tool_name, args|
    if BLOCKED_TOOLS.include?(tool_name)
      Rails.logger.warn("Blocked tool call: #{tool_name} with #{args}")
      return false
    end
    true
  }
)
```

### Audit Logging

Use `on_event` to record every agent action for audit trails:

```ruby
agent = Boxcars::StationAgent.new(
  instructions: "You are a financial assistant.",
  tools: [Boxcars::Calculator.new],
  engine: engine,
  on_event: lambda { |event|
    AuditLog.create!(
      event_type: event.type.to_s,
      data: event.data.to_json,
      iteration: event.iteration,
      occurred_at: event.timestamp
    )
  }
)
```

### Progress UI

Use `run_stream` to feed a progress indicator in a web or CLI UI:

```ruby
agent = Boxcars::StationAgent.new(
  instructions: "You are a research assistant.",
  tools: [Boxcars::GoogleSearch.new, Boxcars::Calculator.new],
  engine: engine
)

agent.run_stream("Analyze the top 5 tech companies by market cap") do |event|
  case event.type
  when :agent_start
    render_status("Agent started...")
  when :llm_call_start
    render_status("Thinking (iteration #{event.data[:iteration]})...")
  when :tool_call_start
    render_status("Using #{event.data[:tool_name]}...")
  when :tool_call_end
    render_status("#{event.data[:tool_name]} done (#{event.data[:duration_ms]}ms)")
  when :agent_complete
    render_status("Complete! (#{event.data[:iterations]} iterations, #{event.data[:tool_calls_count]} tool calls)")
  end
end
```
