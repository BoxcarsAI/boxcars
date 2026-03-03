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
- Multiple orchestration modes: keep legacy text ReAct (`Boxcars::ZeroShot`) or use native provider tool calling (`Boxcars::ToolTrain`).
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

## Concepts

All of these concepts are in a module named Boxcars:

- **Boxcar** — a single-purpose tool (search, math, SQL, Active Record query, API call). Can use an Engine for LLM work.
- **Train** — given a list of Boxcars and an Engine, breaks down a problem for individual Boxcars to solve. `Boxcars::ZeroShot` (legacy ReAct) and `Boxcars::ToolTrain` (native tool calling).
- **Prompt** — used by an Engine to generate text results. Built-in prompts are provided, but you can customize them.
- **Engine** — generates text from a Prompt. Supports OpenAI, Anthropic, Groq, Gemini, Perplexity, Ollama, Together, Cerebras, and more.
- **StationAgent** — a higher-level agent abstraction over Train with lifecycle callbacks, agent-as-tool nesting, handoffs, and event streaming. See the [Agents Guide](./docs/agents_guide.md).
- **VectorStore** — a place to store and query vectors.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'boxcars'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install boxcars

### Optional Provider Dependencies

`boxcars` keeps provider/tooling dependencies optional so base installs stay lean.
Add only the gems you use:

```ruby
gem "openai", ">= 0.30"    # OpenAI + OpenAI-compatible engines
gem "ruby-anthropic"       # Boxcars::Anthropic
gem "google_search_results" # Boxcars::GoogleSearch
gem "faraday"              # Boxcars::Perplexityai / Boxcars::Cohere
gem "activerecord"         # Boxcars::ActiveRecord / Boxcars::SQLActiveRecord (non-Rails usage)
gem "sequel"               # Boxcars::SQLSequel
gem "pg"                   # Pgvector vector-store backend
gem "pgvector"             # Pgvector vector-store backend
gem "nokogiri"             # XML trains, URLText HTML extraction
gem "hnswlib"              # HNSW vector store paths
```

If a feature is used without its optional gem installed, Boxcars raises a setup error with the gem name to add.

## Quick Start

### Single Boxcar

```ruby
calc = Boxcars::Calculator.new
puts calc.run("What is pi to the fourth power divided by 22.1?")
# => 4.407651178009159
```

### Train (Multi-Tool Orchestration)

```ruby
boxcars = [Boxcars::Calculator.new, Boxcars::GoogleSearch.new]
train = Boxcars.train.new(boxcars: boxcars)
puts train.run("What is pi times the square root of the average temperature in Austin TX in January?")
```

### Agent

```ruby
agent = Boxcars::StationAgent.new(
  instructions: "You are a helpful math tutor.",
  tools: [Boxcars::Calculator.new],
  model: "sonnet"
)
puts agent.run("What is the square root of 144?")
```

## Guides

| Guide | Covers |
|---|---|
| [Boxcars Guide](./docs/boxcars_guide.md) | Engines, Boxcars, Trains, MCP, Observability, JSON Schema, configuration |
| [Agents Guide](./docs/agents_guide.md) | StationAgent, AgentRunner, handoffs, event streaming, lifecycle callbacks |
| [UPGRADING.md](./UPGRADING.md) | Migration guidance for v1.0 (tool-calling, alias deprecations, OpenAI client) |

## Security

Both `ActiveRecord` and the SQL boxcars default to **read-only mode**, rejecting write operations with a `Boxcars::SecurityError`. To allow writes, disable read-only mode or provide an approval callback. See the [Boxcars Guide](./docs/boxcars_guide.md#read-only-defaults-and-security) for details and examples.

### Current Upgrade Notes (toward v1.0)

- `Boxcars::Openai` now defaults to `gpt-5-mini` and uses the official OpenAI client path.
- `Boxcars::Cohere` now defaults to `command-a-03-2025` (legacy `command-r*` model IDs were retired by Cohere).
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

## More Examples

- [Boxcars examples notebook](https://github.com/BoxcarsAI/boxcars/blob/main/notebooks/boxcars_examples.ipynb)
- [Swagger examples notebook](https://github.com/BoxcarsAI/boxcars/blob/main/notebooks/swagger_examples.ipynb)
- [Vector search examples notebook](https://github.com/BoxcarsAI/boxcars/blob/main/notebooks/vector_search_examples.ipynb)

Note, some folks that we talked to didn't know that you could run Ruby Jupyter notebooks. [You can](https://github.com/SciRuby/iruby).

## Logging

Configure logging with `Boxcars.configuration.logger = your_logger` and enable prompt debugging with `Boxcars.configuration.log_prompts = true`. See the [Boxcars Guide](./docs/boxcars_guide.md#logging) for details.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/BoxcarsAI/boxcars. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/BoxcarsAI/boxcars/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Boxcars project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/BoxcarsAI/boxcars/blob/main/CODE_OF_CONDUCT.md).
