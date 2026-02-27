<h2 align="center">Boxcars</h2>

<h4 align="center">
  <a href="https://www.boxcars.ai">Website</a> |
  <a href="https://www.boxcars.ai/blog">Blog</a> |
  <a href="https://github.com/BoxcarsAI/boxcars/wiki">Documentation</a>
</h4>

<p align="center">
  <a href="https://github.com/BoxcarsAI/boxcars/blob/main/LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-informational" alt="License"></a>
</p>

Boxcars is a Ruby framework for building LLM-powered systems with less cognitive load, especially for Ruby and Rails teams.
If you want one gem that can search, calculate, query data, call external APIs, run retrieval, and coordinate all of that in one runtime, Boxcars is built for that workflow.

Inspired by LangChain, Boxcars brings a Ruby-first design that favors practical composition over framework lock-in.

## Why Boxcars

- Tool composability by default: package domain logic as `Boxcar` objects and reuse them across assistants, jobs, and services.
- Lower cognitive load for Ruby/Rails developers: one consistent programming model (`Boxcar`, `Train`, `Engine`) for controllers, jobs, and service objects instead of one-off wrappers per provider.
- Multiple orchestration modes: keep legacy text ReAct (`Boxcars::ZeroShot`) or use native provider tool calling (`Boxcars::ToolCallingTrain`).
- Structured output paths: enforce JSON contracts with JSON Schema through `JSONEngineBoxcar`.
- MCP-ready integration: connect MCP servers over stdio and merge MCP tools with local Boxcars in one tool-calling runtime.
- Provider flexibility without a rewrite: use OpenAI, Anthropic, Groq, Gemini, Ollama, Perplexity, and more through shared engine patterns.
- Data-aware workflows: combine SQL, ActiveRecord, vector search, and API-backed tools in one train for end-to-end tasks.
- Incremental migration strategy: modernize from older aliases/runtime paths without breaking existing apps in one big cutover.

## What You Can Build Quickly

- Internal copilots that can search docs, inspect SQL/ActiveRecord data, and answer with auditable tool traces.
- Operations bots that call Swagger-defined APIs and business tools to complete multi-step actions.
- Retrieval-first assistants that combine embeddings/vector search with deterministic follow-up tool calls.
- Local+remote agent workflows that blend your own Ruby tools with MCP-discovered tools.

Upgrading guidance for the ongoing modernization work (native tool-calling, MCP, JSON Schema support, alias deprecations, and official OpenAI client migration) is in [`UPGRADING.md`](./UPGRADING.md).
Notebook migration expectations for the OpenAI client migration are documented in the "Notebook compatibility matrix" section of [`UPGRADING.md`](./UPGRADING.md#notebook-compatibility-matrix-v09).

### Current Upgrade Notes (toward v1.0)

- `Boxcars::Openai` now defaults to `gpt-5-mini` and uses the official OpenAI client path.
- Runtime ActiveSupport/ActiveRecord targets are now `~> 8.1`.
- Swagger workflows now use Faraday guidance. `rest-client` is no longer a Boxcars runtime dependency.
- `intelligence` and `gpt4all` are now optional dependencies:
  - Core Boxcars usage no longer requires either gem.
  - `Boxcars::IntelligenceBase` requires `gem "intelligence"` in your app.
  - `Boxcars::Gpt4allEng` requires `gem "gpt4all"` in your app.
- OpenAI and OpenAI-compatible engines now use the official OpenAI client path (OpenAI, Groq, Gemini, Ollama, Google, Cerebras, Together).

If your app uses `IntelligenceBase` or `Gpt4allEng`, add optional gems explicitly:

```ruby
# Gemfile (only if you use these paths)
gem "intelligence"
gem "gpt4all"
```

## Concepts
All of these concepts are in a module named Boxcars:

- Boxcar - an encapsulation that performs something of interest (such as search, math, SQL, an Active Record Query, or an API call to a service). A Boxcar can use an Engine (described below) to do its work, and if not specified but needed, the default Engine is used `Boxcars.engine`.
- Train - Given a list of Boxcars and optionally an Engine, a Train breaks down a problem into pieces for individual Boxcars to solve. The individual results are then combined until a final answer is found. `Boxcars::ZeroShot` is the legacy text ReAct implementation, and `Boxcars::ToolCallingTrain` is the newer native tool-calling runtime.
- Prompt - used by an Engine to generate text results. Our Boxcars have built-in prompts, but you have the flexibility to change or augment them if you so desire.
- Engine - an entity that generates text from a Prompt. OpenAI's LLM text generator is the default Engine if no other is specified, and you can override the default engine if so desired (`Boxcars.configuration.default_engine`). We have an Engine for Anthropic's Claude API named `Boxcars::Anthropic`, and another Engine for local GPT named `Boxcars::Gpt4allEng` (requires the optional `gpt4all` gem).
- VectorStore - a place to store and query vectors.

## Security
Currently, our system is designed for individuals who already possess administrative privileges for their project. It is likely possible to manipulate the system's prompts to carry out malicious actions, but if you already have administrative access, you can perform such actions without requiring boxcars in the first place.

*Note:* We are actively seeking ways to improve our system's ability to identify and prevent any nefarious attempts from occurring. If you have any suggestions or recommendations, please feel free to share them with us by either finding an existing issue or creating a new one and providing us with your feedback.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'boxcars'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install boxcars

## Usage

First, set environment variables for providers you plan to use (for example `OPENAI_ACCESS_TOKEN` or `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `SERPAPI_API_KEY`). If you prefer, you can pass keys directly in code.

In the examples below, we use one extra gem to load environment variables; depending on your setup, you may not need it.
```ruby
require "dotenv/load"
require "boxcars"
```

Note: if you want to try out the examples below, run this command and then paste in the code segments of interest:
```bash
irb -r dotenv/load -r boxcars

# or if you prefer local repository
irb -r dotenv/load -r ./lib/boxcars
```

### Rails Quickstart (Low Cognitive Load Path)

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

Note that since OpenAI is currently the most used engine, if you do not pass an engine, Boxcars will use its default engine. This is the equivalent shorter version:
```ruby
# run the calculator
calc = Boxcars::Calculator.new # just use the default Engine
puts calc.run "what is pi to the fourth power divided by 22.1?"
```
You can change the default engine with `Boxcars.configuration.default_engine = NewDefaultEngine`
### Built-in Boxcars and Capabilities

Boxcars ships with high-leverage tools you can compose immediately, and you can add your own domain-specific Boxcars as needed.

- `GoogleSearch`: uses SERP API for live web lookup.
- `WikipediaSearch`: uses Wikipedia API for fast factual retrieval.
- `Calculator`: uses an engine to produce/execute Ruby math logic.
- `SQL`: generates and executes SQL from prompts using your ActiveRecord connection.
- `ActiveRecord`: generates and executes ActiveRecord code from prompts.
- `Swagger`: consumes OpenAPI (YAML/JSON) to answer questions about and run against API endpoints. See [Swagger notebook examples](https://github.com/BoxcarsAI/boxcars/blob/main/notebooks/swagger_examples.ipynb).
- `VectorStore` workflows: embed, persist, and retrieve context for RAG-like retrieval flows (see vector notebooks).

### Run a list of Boxcars
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

Next Actions:
1. What is the average temperature in Austin TX in July?
2. What is the value of pi to 10 decimal places?
3. What is the square root of the average temperature in Miami FL in January?
< Exiting Zero Shot#run
```

### MCP Tools with Native Tool Calling

You can connect an MCP server over `stdio`, wrap its tools as Boxcars, and run them with the newer native tool-calling train:

```ruby
require "boxcars"

engine = Boxcars::Engines.engine(model: "gpt-4o")
mcp_client = Boxcars::MCP.stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"])

begin
  train = Boxcars::MCP.tool_calling_train(
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

`Boxcars::MCP.tool_calling_train(...)` combines local Boxcars and MCP-discovered tools into a `Boxcars::ToolCallingTrain`.

### More Examples
See [this](https://github.com/BoxcarsAI/boxcars/blob/main/notebooks/boxcars_examples.ipynb) Jupyter Notebook for more examples.

For the Swagger boxcar, see [this](https://github.com/BoxcarsAI/boxcars/blob/main/notebooks/swagger_examples.ipynb) Jupyter Notebook.

For simple vector storage and search, see [this](https://github.com/BoxcarsAI/boxcars/blob/main/notebooks/vector_search_examples.ipynb) Jupyter Notebook.

Note, some folks that we talked to didn't know that you could run Ruby Jupyter notebooks. [You can](https://github.com/SciRuby/iruby).

### Logging
If you use this in a Rails application, or configure `Boxcars.configuration.logger = your_logger`, logging will go to your log file.

Also, if you set this flag: `Boxcars.configuration.log_prompts = true`
The actual prompts handed to the connected Engine will be logged. This is off by default because it is very wordy, but handy if you are debugging prompts.

Otherwise, we print to standard out.

### Engine Factory (Engines)

Boxcars provides a convenient factory class `Boxcars::Engines` that simplifies creating engine instances using model names and aliases instead of remembering full class names and model strings.

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

Some older aliases are still supported but now emit a one-time deprecation warning (per process) to make future pruning safer.

Examples of deprecated aliases:
- `"anthropic"` (use `"sonnet"`)
- `"groq"` (use an explicit model like `"llama-3.3-70b-versatile"`)
- `"online"` / `"huge"` / `"online_huge"` (use `"sonar"` / `"sonar-pro"`)
- `"sonar_huge"` / `"sonar-huge"` / `"sonar_pro"` (use `"sonar-pro"`)
- `"flash"` / `"gemini-flash"` / `"gemini-pro"` (use explicit Gemini models)
- `"deepseek"`, `"mistral"`, `"cerebras"`, `"qwen"` (use explicit model names)

`"sonar"` and `"sonar-pro"` remain supported curated aliases.

To enforce migration in CI or during upgrades, enable strict mode to raise an error instead of warning when a deprecated alias is used:

```ruby
Boxcars.configure do |config|
  config.strict_deprecated_model_aliases = true
end

# or:
Boxcars::Engines.strict_deprecated_aliases = true
```

#### OpenAI Client Setup (v0.9+)

`Boxcars::Openai` and OpenAI-compatible providers use the official OpenAI client path.

```ruby
# Optional: require true native official wiring and fail if no official client is wired.
ENV["OPENAI_OFFICIAL_REQUIRE_NATIVE"] = "true"

# Per-engine setting
engine = Boxcars::Openai.new(model: "gpt-5-mini")

# Per-call usage
engine.run("Write a one-line summary")
```

Groq, Gemini, Ollama, Google, Cerebras, and Together all use the same official OpenAI client path with provider-specific base URLs.

If you want explicit control over the official SDK client shape, you can provide a client builder:

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

For OpenAI client parity checks:

```bash
bundle exec rake spec:openai_client_parity
bundle exec rake spec:openai_client_parity_official
# full modernization regression lane:
bundle exec rake spec:modernization
```

To fail fast on client wiring issues at boot time:

```ruby
Boxcars::OpenAICompatibleClient.validate_client_configuration!
```

This preflight validates that official client wiring is available before runtime calls.

#### JSON-Optimized Engines

For applications requiring JSON responses, use the `json_engine` method:

```ruby
# Creates engine optimized for JSON output
json_engine = Boxcars::Engines.json_engine(model: "gpt-4o")

# Automatically removes response_format for models that don't support it
json_claude = Boxcars::Engines.json_engine(model: "sonnet")
```

#### `JSONEngineBoxcar` for Typed App Workflows

`JSONEngineBoxcar` is designed for application code paths where you want structured fields instead of prompt-parsing strings.
In real-world `apiserver` usage, this wrapper has been a major time saver for keeping LLM responses predictable.
With JSON Schema support, it can now validate output contracts directly in the boxcar layer.

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

#### Using with Boxcars

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

### Overriding the Default Engine Model

Boxcars provides several ways to override the default engine model used throughout your application. The default model is currently `"gemini-2.5-flash"` in `Boxcars::Engines`, but you can customize this behavior.

#### Global Configuration

Set a global default model that will be used by `Boxcars::Engines.engine()` when no model is specified:

```ruby
# Set the default model globally
Boxcars.configuration.default_model = "gpt-4o"

# Now all engines created without specifying a model will use GPT-4o
engine = Boxcars::Engines.engine  # Uses gpt-4o
calc = Boxcars::Calculator.new    # Uses gpt-4o via default engine
```

#### Configuration Block

Use a configuration block for more organized setup:

```ruby
Boxcars.configure do |config|
  config.default_model = "sonnet"  # Use Claude Sonnet as default
  config.logger = Rails.logger     # Set custom logger
  config.log_prompts = true        # Enable prompt logging
end
```

#### Per-Instance Override

Override the model for specific engine instances:

```ruby
# Global default is gemini-flash, but use different models per boxcar
default_engine = Boxcars::Engines.engine                    # Uses global default
gpt_engine = Boxcars::Engines.engine(model: "gpt-4o")       # Uses GPT-4o
claude_engine = Boxcars::Engines.engine(model: "sonnet")    # Uses Claude Sonnet

# Use different engines for different boxcars
calc = Boxcars::Calculator.new(engine: gpt_engine)
search = Boxcars::GoogleSearch.new(engine: claude_engine)
```

#### Environment-Based Configuration

Set the default model via environment variables or initialization:

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

The `Boxcars::Engines.engine()` method resolves the model in this order:

1. **Explicit model parameter**: `Boxcars::Engines.engine(model: "gpt-4o")`
2. **Global configuration**: `Boxcars.configuration.default_model`
3. **Built-in default**: `"gemini-2.5-flash"`

#### Supported Model Aliases

When setting `default_model`, you can use any supported explicit model name plus curated aliases:

```ruby
# These are all valid default_model values:
Boxcars.configuration.default_model = "gpt-4o"        # OpenAI GPT-4o
Boxcars.configuration.default_model = "sonnet"        # Claude Sonnet
Boxcars.configuration.default_model = "gemini-2.5-flash" # Gemini Flash
Boxcars.configuration.default_model = "sonar"         # Perplexity Sonar
Boxcars.configuration.default_model = "sonar-pro"     # Perplexity Sonar Pro
```

#### Legacy Engine Configuration

You can also override the default engine class (though this is less common):

```ruby
# Override the default engine class entirely
Boxcars.configuration.default_engine = Boxcars::Anthropic

# Now Boxcars.engine returns Anthropic instead of OpenAI
default_engine = Boxcars.engine  # Returns Boxcars::Anthropic instance
```

**Note**: When using `default_engine`, the `default_model` setting is ignored since you're specifying the engine class directly.

### Observability

Boxcars includes a comprehensive observability system that allows you to track and monitor AI operations across your application. The system provides insights into LLM calls, performance metrics, errors, and usage patterns.

#### Core Components

**Observability Class**: The central tracking interface that provides a simple `track` method for recording events.

**ObservabilityBackend Module**: An interface that defines how tracking backends should be implemented. All backends must include this module and implement a `track` method.

**Built-in Backends**:
- **PosthogBackend**: Sends events to PostHog for analytics and user behavior tracking
- **MultiBackend**: Allows sending events to multiple backends simultaneously

#### Configuration

Set up observability by configuring a backend:

```ruby
# Using PostHog backend
require 'boxcars/observability_backends/posthog_backend'
require 'posthog'

# Create a PostHog client with your desired configuration
posthog_client = PostHog::Client.new(
  api_key: ENV['POSTHOG_API_KEY'] || 'your_posthog_api_key',
  host: 'https://app.posthog.com', # or your self-hosted instance
  on_error: proc { |status, body| 
    Rails.logger.warn "PostHog error: #{status} - #{body}" 
  }
)

Boxcars.configure do |config|
  config.observability_backend = Boxcars::PosthogBackend.new(client: posthog_client)
end

# Using multiple backends
require 'boxcars/observability_backends/multi_backend'

# Create PostHog client
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

#### Automatic Tracking

Boxcars automatically tracks LLM calls with detailed metrics:

```ruby
# This automatically generates observability events
engine = Boxcars::Openai.new(user_id: USER_ID) # optional user_id. All engines take this.
calc = Boxcars::Calculator.new(engine: engine)
result = calc.run "what is 2 + 2?"
```

**Tracked Properties Include**:
- `provider`: The LLM provider (e.g., "openai", "anthropic")
- `model_name`: The specific model used
- `prompt_content`: The conversation messages sent to the LLM
- `inputs`: Any template inputs provided
- `duration_ms`: Request duration in milliseconds
- `success`: Whether the call succeeded
- `status_code`: HTTP response status
- `error_message`: Error details if the call failed
- `response_raw_body`: Raw API response
- `api_call_parameters`: Parameters sent to the API
- `distinct_id`: If you specify a user_id to your engine, it will be passed up.

#### Manual Tracking

You can also track custom events:

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

#### Creating Custom Backends

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

#### Error Handling

The observability system is designed to fail silently to prevent tracking issues from disrupting your main application flow. If a backend raises an error, it will be caught and ignored, ensuring your AI operations continue uninterrupted.

#### PostHog Integration

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


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/BoxcarsAI/boxcars. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/BoxcarsAI/boxcars/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Boxcars project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/BoxcarsAI/boxcars/blob/main/CODE_OF_CONDUCT.md).
