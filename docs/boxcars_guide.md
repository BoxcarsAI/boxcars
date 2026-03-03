# Boxcars Guide

This guide covers the core Boxcars framework: **Engines**, **Boxcars** (tools), **Trains** (orchestration), **MCP integration**, and **Observability**.

For the agent layer (StationAgent, AgentRunner, handoffs, event streaming), see the [Agents Guide](./agents_guide.md).

## Overview

Three core abstractions form a pipeline:

- **Engine** — LLM provider abstraction (OpenAI, Anthropic, Groq, Gemini, Perplexity, Ollama, Together, Cerebras, Cohere)
- **Boxcar** — a single-purpose tool (Calculator, SQL, ActiveRecord, GoogleSearch, Swagger, VectorStore, etc.)
- **Train** — an orchestrator that runs a series of Boxcars using an Engine to break down and solve problems

## Quick Start

### Environment Setup

Set environment variables for providers you plan to use (e.g., `OPENAI_ACCESS_TOKEN` or `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `SERPAPI_API_KEY`). You can also pass keys directly in code.

```ruby
require "dotenv/load"
require "boxcars"
```

To try out examples interactively:

```bash
irb -r dotenv/load -r boxcars

# or if you prefer local repository
irb -r dotenv/load -r ./lib/boxcars
```

### Rails Initializer Pattern

Use a Rails initializer for defaults, then call Boxcars from normal service objects.

```ruby
# config/initializers/boxcars.rb
Boxcars.configure do |config|
  config.default_model = "gpt-5-mini"
  config.log_prompts = Rails.env.development?
end
```

```ruby
# app/services/ai/summarize_ticket.rb
class Ai::SummarizeTicket
  SCHEMA = {
    type: "object",
    properties: {
      summary: { type: "string" },
      priority: { type: "string", enum: ["low", "medium", "high"] }
    },
    required: ["summary", "priority"],
    additionalProperties: false
  }.freeze

  def call(text)
    boxcar = Boxcars::JSONEngineBoxcar.new(
      engine: Boxcars::Engines.engine(model: "gpt-5-mini"),
      json_schema: SCHEMA
    )

    boxcar.run("Summarize this support ticket and set priority:\n\n#{text}")
  end
end
```

This keeps LLM integration close to standard Rails patterns while avoiding custom prompt-parsing glue code.

## Engines

### Engine Factory (Boxcars::Engines)

`Boxcars::Engines` is a factory class that creates engine instances from model names and aliases.

#### Basic Usage

```ruby
# Using default model (gemini-2.5-flash)
engine = Boxcars::Engines.engine

# Using specific models and curated aliases
gpt_engine = Boxcars::Engines.engine(model: "gpt-4o")
claude_engine = Boxcars::Engines.engine(model: "sonnet")
gemini_engine = Boxcars::Engines.engine(model: "gemini-2.5-flash")
perplexity_engine = Boxcars::Engines.engine(model: "sonar")
```

#### Supported Model Aliases

**OpenAI Models:**
- Any OpenAI model ID from the [OpenAI pricing/models page](https://developers.openai.com/api/pricing) (for example `"gpt-5-mini"`, `"gpt-5"`, `"o1"`, `"o3"`) creates `Boxcars::Openai` engines

**Anthropic Models:**
- `"anthropic"`, `"sonnet"` - Creates `Boxcars::Anthropic` with Claude Sonnet
- `"opus"` - Creates `Boxcars::Anthropic` with Claude Opus
- `"claude-3-5-sonnet"`, etc. - Any model starting with "claude-"

**Groq Models:**
- `"groq"` - Creates `Boxcars::Groq` with Llama 3.3 70B
- `"deepseek"` - Creates `Boxcars::Groq` with DeepSeek R1
- `"mistral"` - Creates `Boxcars::Groq` with Mistral
- Models starting with `"mistral-"`, `"meta-llama/"`, or `"deepseek-"`

**Gemini Models:**
- `"flash"`, `"gemini-flash"` - Creates `Boxcars::GeminiAi` with Gemini 2.5 Flash
- `"gemini-pro"` - Creates `Boxcars::GeminiAi` with Gemini 2.5 Pro
- Any model starting with `"gemini-"`

**Perplexity Models:**
- `"online"`, `"sonar"` - Creates `Boxcars::Perplexityai` with Sonar
- `"sonar-pro"`, `"huge"` - Creates `Boxcars::Perplexityai` with Sonar Pro
- Models containing `"-sonar-"`

**Together AI Models:**
- `"together-model-name"` - Creates `Boxcars::Together` (strips "together-" prefix)

#### Alias Deprecations (Migration to v1.0)

Some older aliases are still supported but emit a one-time deprecation warning (per process):

- `"anthropic"` (use `"sonnet"`)
- `"groq"` (use an explicit model like `"llama-3.3-70b-versatile"`)
- `"online"` / `"huge"` / `"online_huge"` (use `"sonar"` / `"sonar-pro"`)
- `"sonar_huge"` / `"sonar-huge"` / `"sonar_pro"` (use `"sonar-pro"`)
- `"flash"` / `"gemini-flash"` / `"gemini-pro"` (use explicit Gemini models)
- `"deepseek"`, `"mistral"`, `"cerebras"`, `"qwen"` (use explicit model names)

`"sonar"` and `"sonar-pro"` remain supported curated aliases.

Enable strict mode to raise an error instead of warning on deprecated aliases:

```ruby
Boxcars.configure do |config|
  config.strict_deprecated_model_aliases = true
end

# or:
Boxcars::Engines.strict_deprecated_aliases = true
```

Temporarily silence deprecation warnings during migration:

```ruby
Boxcars.configure do |config|
  config.emit_deprecation_warnings = false
end
```

#### Passing Additional Parameters

```ruby
# Pass any additional parameters to the underlying engine
engine = Boxcars::Engines.engine(
  model: "gpt-4o",
  temperature: 0.7,
  max_tokens: 1000,
  top_p: 0.9
)
```

### OpenAI Client Setup

`Boxcars::Openai` and OpenAI-compatible providers use the official OpenAI client path (v0.9+).

```ruby
# Optional: require true native official wiring and fail if no official client is wired.
ENV["OPENAI_OFFICIAL_REQUIRE_NATIVE"] = "true"

# Per-engine setting
engine = Boxcars::Openai.new(model: "gpt-5-mini")

# Per-call usage
engine.run("Write a one-line summary")
```

Groq, Gemini, Ollama, Google, Cerebras, and Together all use the same official OpenAI client path with provider-specific base URLs.

#### Custom Client Builder

If you want explicit control over the official SDK client shape:

```ruby
Boxcars.configure do |config|
  config.openai_official_client_builder = lambda do |access_token:, uri_base:, organization_id:, log_errors:|
    OpenAI::Client.new(
      api_key: access_token,
      base_url: uri_base,
      organization: organization_id
    )
  end
end
```

If you set `OPENAI_OFFICIAL_REQUIRE_NATIVE=true` (or `config.openai_official_require_native = true`), Boxcars will fail fast unless native official wiring is available.

#### Preflight Validation

To fail fast on client wiring issues at boot time:

```ruby
Boxcars::OpenAIClient.validate_client_configuration!
```

For parity checks:

```bash
bundle exec rake spec:deprecation_guards
bundle exec rake spec:openai_client_parity
bundle exec rake spec:openai_client_parity_official
bundle exec rake spec:minimal_dependencies
# full modernization regression lane:
bundle exec rake spec:modernization
```

### JSON-Optimized Engines

For applications requiring JSON responses, use the `json_engine` method:

```ruby
# Creates engine optimized for JSON output
json_engine = Boxcars::Engines.json_engine(model: "gpt-4o")

# Automatically removes response_format for models that don't support it
json_claude = Boxcars::Engines.json_engine(model: "sonnet")
```

#### JSONEngineBoxcar with JSON Schema

`JSONEngineBoxcar` is designed for application code paths where you want structured fields instead of prompt-parsing strings. With JSON Schema support, it validates output contracts directly in the boxcar layer. When the selected engine supports native structured outputs, Boxcars sends the schema directly to the provider API (including OpenAI Responses models like `gpt-5-*`).

```ruby
schema = {
  type: "object",
  properties: {
    answer: { type: "string" },
    confidence: { type: ["number", "null"] }
  },
  required: ["answer"],
  additionalProperties: false
}

extractor = Boxcars::JSONEngineBoxcar.new(
  engine: Boxcars::Engines.engine(model: "gpt-4o"),
  json_schema: schema
)

result = extractor.run("What is the best one-line summary of this ticket?")
# => { status: "ok", answer: { "answer" => "...", "confidence" => 0.92 }, ... }
```

If you need a softer rollout during migration, use `json_schema_strict: false` and tighten to strict mode once outputs are stable.

### Overriding Defaults

#### Global Configuration

Set a global default model used by `Boxcars::Engines.engine()` when no model is specified:

```ruby
# Set the default model globally
Boxcars.configuration.default_model = "gpt-4o"

# Now all engines created without specifying a model will use GPT-4o
engine = Boxcars::Engines.engine  # Uses gpt-4o
calc = Boxcars::Calculator.new    # Uses gpt-4o via default engine
```

#### Configuration Block

```ruby
Boxcars.configure do |config|
  config.default_model = "sonnet"  # Use Claude Sonnet as default
  config.logger = Rails.logger     # Set custom logger
  config.log_prompts = true        # Enable prompt logging
end
```

#### Per-Instance Override

```ruby
# Global default is gemini-2.5-flash, but use different models per boxcar
default_engine = Boxcars::Engines.engine                    # Uses global default
gpt_engine = Boxcars::Engines.engine(model: "gpt-4o")       # Uses GPT-4o
claude_engine = Boxcars::Engines.engine(model: "sonnet")    # Uses Claude Sonnet

# Use different engines for different boxcars
calc = Boxcars::Calculator.new(engine: gpt_engine)
search = Boxcars::GoogleSearch.new(engine: claude_engine)
```

#### Environment-Based Configuration

```ruby
# In your application initialization (e.g., Rails initializer)
if Rails.env.production?
  Boxcars.configuration.default_model = "gpt-4o"      # Use GPT-4o in production
elsif Rails.env.development?
  Boxcars.configuration.default_model = "gemini-2.5-flash" # Use faster Gemini Flash in development
else
  Boxcars.configuration.default_model = "llama-3.3-70b-versatile" # Use explicit Groq model for testing
end
```

#### Model Resolution Priority

`Boxcars::Engines.engine()` resolves the model in this order:

1. **Explicit model parameter**: `Boxcars::Engines.engine(model: "gpt-4o")`
2. **Global configuration**: `Boxcars.configuration.default_model`
3. **Built-in default**: `"gemini-2.5-flash"`

#### Supported Model Aliases for default_model

```ruby
# These are all valid default_model values:
Boxcars.configuration.default_model = "gpt-4o"        # OpenAI GPT-4o
Boxcars.configuration.default_model = "sonnet"        # Claude Sonnet
Boxcars.configuration.default_model = "gemini-2.5-flash" # Gemini Flash
Boxcars.configuration.default_model = "sonar"         # Perplexity Sonar
Boxcars.configuration.default_model = "sonar-pro"     # Perplexity Sonar Pro
```

#### Legacy Engine Configuration

You can also override the default engine class (less common):

```ruby
# Override the default engine class entirely
Boxcars.configuration.default_engine = Boxcars::Anthropic

# Now Boxcars.engine returns Anthropic instead of OpenAI
default_engine = Boxcars.engine  # Returns Boxcars::Anthropic instance
```

**Note**: When using `default_engine`, the `default_model` setting is ignored since you're specifying the engine class directly.

## Boxcars (Tools)

### Built-in Boxcars

Boxcars ships with high-leverage tools you can compose immediately:

- **`GoogleSearch`** — uses SERP API for live web lookup.
- **`WikipediaSearch`** — uses Wikipedia API for fast factual retrieval.
- **`Calculator`** — uses an engine to produce/execute Ruby math logic.
- **`SQL`** — generates and executes SQL from prompts using your ActiveRecord connection. Read-only by default.
- **`ActiveRecord`** — generates and executes ActiveRecord code from prompts. Read-only by default.
- **`Swagger`** — consumes OpenAPI (YAML/JSON) to answer questions about and run against API endpoints. See [Swagger notebook examples](https://github.com/BoxcarsAI/boxcars/blob/main/notebooks/swagger_examples.ipynb).
- **`VectorStore`** workflows — embed, persist, and retrieve context for RAG-like retrieval flows (see [vector search notebook](https://github.com/BoxcarsAI/boxcars/blob/main/notebooks/vector_search_examples.ipynb)).

You can add your own domain-specific Boxcars as needed.

### Scoping Queries with `context:`

The `ActiveRecord` and `SQL` boxcars accept an optional `context:` parameter that injects runtime information (current user, tenant, permissions) into the LLM prompt so generated queries are properly scoped:

```ruby
ar = Boxcars::ActiveRecord.new(
  models: [Ticket, Comment],
  context: "The current user is User#42 (admin). Only return this user's records."
)
ar.run("How many open tickets do I have?")

# Update context per-request
ar.context = "The current user is User#99 (viewer)."
ar.run("Show my recent comments")
```

When `context` is `nil` or blank, nothing extra is added to the prompt.

### Read-Only Defaults and Security

Both `ActiveRecord` and the SQL boxcars (`SQLActiveRecord`, `SQLSequel`) default to **read-only mode**, rejecting write operations (INSERT, UPDATE, DELETE, DROP, etc.) with a `Boxcars::SecurityError`.

To allow writes, either disable read-only mode or provide an approval callback:

```ruby
# Option 1: disable read-only (use with caution)
sql = Boxcars::SQLActiveRecord.new(read_only: false)

# Option 2: approval callback for write SQL
sql = Boxcars::SQLActiveRecord.new(approval_callback: ->(sql) { puts "Approve? #{sql}"; true })

# Option 3: approval callback for ActiveRecord (receives change count and code)
ar = Boxcars::ActiveRecord.new(approval_callback: ->(changes, code) { changes < 5 })
```

When an `approval_callback` is provided, read-only defaults to `false` so the callback can decide. You can combine `read_only: true` with a callback to enforce read-only regardless.

### Direct Boxcar Use

```ruby
# run the calculator
engine = Boxcars::Openai.new(max_tokens: 256)
calc = Boxcars::Calculator.new(engine: engine)
puts calc.run "what is pi to the fourth power divided by 22.1?"
```

Produces:

```text
> Entering Calculator#run
what is pi to the fourth power divided by 22.1?
RubyREPL: puts (Math::PI**4)/22.1
Answer: 4.407651178009159

{"status":"ok","answer":"4.407651178009159","explanation":"Answer: 4.407651178009159","code":"puts (Math::PI**4)/22.1"}
< Exiting Calculator#run
4.407651178009159
```

Since OpenAI is the most commonly used engine, if you do not pass one, Boxcars uses its default:

```ruby
calc = Boxcars::Calculator.new # just use the default Engine
puts calc.run "what is pi to the fourth power divided by 22.1?"
```

You can change the default engine with `Boxcars.configuration.default_engine = NewDefaultEngine`.

#### Using Engines with Boxcars

```ruby
# Use the factory with any Boxcar
engine = Boxcars::Engines.engine(model: "sonnet")
calc = Boxcars::Calculator.new(engine: engine)
result = calc.run "What is 15 * 23?"

# Or in a Train
boxcars = [
  Boxcars::Calculator.new(engine: Boxcars::Engines.engine(model: "gpt-4o")),
  Boxcars::GoogleSearch.new(engine: Boxcars::Engines.engine(model: "gemini-2.5-flash"))
]
train = Boxcars.train.new(boxcars: boxcars)
```

## Trains (Orchestration)

### ZeroShot (Legacy ReAct)

`Boxcars::ZeroShot` is the legacy text-based ReAct implementation. It breaks a problem into steps, routes each step to the appropriate boxcar, and combines results.

```ruby
# run a Train for a calculator, and search using default Engine
boxcars = [Boxcars::Calculator.new, Boxcars::GoogleSearch.new]
train = Boxcars.train.new(boxcars: boxcars)
train.run "What is pi times the square root of the average temperature in Austin TX in January?"
```

Produces:

```text
> Entering Zero Shot#run
What is pi times the square root of the average temperature in Austin TX in January?
Thought: We need to find the average temperature in Austin TX in January and then multiply it by pi and the square root of the average temperature. We can use a search engine to find the average temperature in Austin TX in January and a calculator to perform the multiplication.
Question: Average temperature in Austin TX in January
Answer: January Weather in Austin Texas, United States. Daily high temperatures increase by 2°F, from 62°F to 64°F, rarely falling below 45°F or exceeding 76° ...
Observation: January Weather in Austin Texas, United States. Daily high temperatures increase by 2°F, from 62°F to 64°F, rarely falling below 45°F or exceeding 76° ...
Thought: We have found the average temperature in Austin TX in January, which is 64°F. Now we can use a calculator to perform the multiplication.
> Entering Calculator#run
pi * sqrt(64)
RubyREPL: puts(Math::PI * Math.sqrt(64))
Answer: 25.132741228718345

{"status":"ok","answer":"25.132741228718345","explanation":"Answer: 25.132741228718345","code":"puts(Math::PI * Math.sqrt(64))"}
< Exiting Calculator#run
Observation: 25.132741228718345
We have the final answer.

Final Answer: 25.132741228718345
< Exiting Zero Shot#run
```

### ToolTrain (Native Tool Calling)

`Boxcars::ToolTrain` uses native LLM tool-calling APIs instead of text-based ReAct parsing. It is the preferred runtime for new code.

```ruby
engine = Boxcars::Engines.engine(model: "gpt-4o")
boxcars = [Boxcars::Calculator.new, Boxcars::GoogleSearch.new]
train = Boxcars::ToolTrain.new(engine: engine, boxcars: boxcars)
train.run "What is pi times the square root of the average temperature in Austin TX in January?"
```

For agent-level features (instructions DSL, callbacks, nesting, handoffs), see [StationAgent in the Agents Guide](./agents_guide.md).

## MCP Integration

### Connecting MCP Servers

Connect an MCP server over `stdio`, wrap its tools as Boxcars, and run them with native tool calling:

```ruby
require "boxcars"

engine = Boxcars::Engines.engine(model: "gpt-4o")
mcp_client = Boxcars::MCP.stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"])

begin
  train = Boxcars::MCP.tool_train(
    engine: engine,
    boxcars: [Boxcars::Calculator.new],
    clients: [mcp_client],
    client_name_prefixes: { 0 => "Filesystem" }
  )

  puts train.run("What files are in /tmp and what is 12 * 9?")
ensure
  mcp_client.close
end
```

`Boxcars::MCP.tool_train(...)` combines local Boxcars and MCP-discovered tools into a `Boxcars::ToolTrain`.

### Combining Local and MCP Tools

You can mix local boxcar tools and MCP tools freely:

```ruby
mcp_client = Boxcars::MCP.stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"])

begin
  train = Boxcars::MCP.tool_train(
    engine: Boxcars::Engines.engine(model: "gpt-4o"),
    boxcars: [Boxcars::Calculator.new, Boxcars::GoogleSearch.new],
    clients: [mcp_client]
  )
  puts train.run("Search for Ruby 3.4 features and list files in /tmp")
ensure
  mcp_client.close
end
```

For MCP tools with StationAgent, see the [Agents Guide](./agents_guide.md#using-mcp-tools).

## Observability

Boxcars includes a comprehensive observability system for tracking and monitoring AI operations.

### Core Components

- **Observability** — central tracking interface with a `track` method for recording events
- **ObservabilityBackend** — interface that all backends must implement
- **PosthogBackend** — sends events to PostHog for analytics
- **MultiBackend** — sends events to multiple backends simultaneously

### Configuration

```ruby
# Using PostHog backend
require 'boxcars/observability_backends/posthog_backend'
require 'posthog'

posthog_client = PostHog::Client.new(
  api_key: ENV['POSTHOG_API_KEY'] || 'your_posthog_api_key',
  host: 'https://app.posthog.com',
  on_error: proc { |status, body|
    Rails.logger.warn "PostHog error: #{status} - #{body}"
  }
)

Boxcars.configure do |config|
  config.observability_backend = Boxcars::PosthogBackend.new(client: posthog_client)
end
```

#### MultiBackend

```ruby
require 'boxcars/observability_backends/multi_backend'

posthog_client = PostHog::Client.new(
  api_key: ENV['POSTHOG_API_KEY'],
  host: 'https://app.posthog.com'
)
backend1 = Boxcars::PosthogBackend.new(client: posthog_client)
backend2 = YourCustomBackend.new

Boxcars.configure do |config|
  config.observability_backend = Boxcars::MultiBackend.new([backend1, backend2])
end
```

### Automatic Tracking

Boxcars automatically tracks LLM calls with detailed metrics:

```ruby
engine = Boxcars::Openai.new(user_id: USER_ID) # optional user_id. All engines take this.
calc = Boxcars::Calculator.new(engine: engine)
result = calc.run "what is 2 + 2?"
```

**Tracked Properties:**
- `provider` — the LLM provider (e.g., "openai", "anthropic")
- `model_name` — the specific model used
- `prompt_content` — the conversation messages sent to the LLM
- `inputs` — any template inputs provided
- `duration_ms` — request duration in milliseconds
- `success` — whether the call succeeded
- `status_code` — HTTP response status
- `error_message` — error details if the call failed
- `response_raw_body` — raw API response
- `api_call_parameters` — parameters sent to the API
- `distinct_id` — if you specify a user_id to your engine, it will be passed up

### Manual Tracking

```ruby
Boxcars::Observability.track(
  event: 'custom_operation',
  properties: {
    user_id: 'user_123',
    operation_type: 'data_processing',
    duration_ms: 150,
    success: true
  }
)
```

### Custom Backends

Implement your own backend by including the `ObservabilityBackend` module:

```ruby
class CustomBackend
  include Boxcars::ObservabilityBackend

  def track(event:, properties:)
    # Your custom tracking logic here
    puts "Event: #{event}, Properties: #{properties}"
  end
end

Boxcars.configure do |config|
  config.observability_backend = CustomBackend.new
end
```

### PostHog Integration

The PostHog backend requires the `posthog-ruby` gem:

```ruby
# Add to your Gemfile
gem 'posthog-ruby'

# Configure the backend
require 'posthog'

posthog_client = PostHog::Client.new(
  api_key: ENV['POSTHOG_API_KEY'],
  host: 'https://app.posthog.com',
  on_error: proc { |status, body|
    Rails.logger.warn "PostHog error: #{status} - #{body}"
  }
)

Boxcars.configure do |config|
  config.observability_backend = Boxcars::PosthogBackend.new(client: posthog_client)
end
```

Events are automatically associated with users when a `user_id` property is provided. Anonymous events use a default identifier.

### Error Handling

The observability system is designed to fail silently to prevent tracking issues from disrupting your main application flow. If a backend raises an error, it will be caught and ignored.

## Logging

If you use Boxcars in a Rails application, or configure `Boxcars.configuration.logger = your_logger`, logging goes to your log file.

Enable prompt logging for debugging:

```ruby
Boxcars.configuration.log_prompts = true
```

This logs the actual prompts sent to the Engine. It is off by default because it is verbose, but handy for debugging.

Otherwise, output goes to standard out.

## Additional Resources

- [Boxcars examples notebook](https://github.com/BoxcarsAI/boxcars/blob/main/notebooks/boxcars_examples.ipynb)
- [Swagger examples notebook](https://github.com/BoxcarsAI/boxcars/blob/main/notebooks/swagger_examples.ipynb)
- [Vector search examples notebook](https://github.com/BoxcarsAI/boxcars/blob/main/notebooks/vector_search_examples.ipynb)
- [Agents Guide](./agents_guide.md) — StationAgent, AgentRunner, handoffs, event streaming
- [UPGRADING.md](../UPGRADING.md) — migration guidance for native tool-calling, MCP, JSON Schema, alias deprecations, and OpenAI client migration

Note: some folks that we talked to didn't know that you could run Ruby Jupyter notebooks. [You can](https://github.com/SciRuby/iruby).
