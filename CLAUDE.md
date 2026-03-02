# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Boxcars is a Ruby gem for building LLM-powered systems with tool composition and orchestration. It provides abstractions for LLM engines, single-purpose tools (boxcars), and orchestrators (trains) that chain tools together.

## Common Commands

```bash
bundle exec rake spec              # Run full test suite
bundle exec rspec spec/boxcars/calculator_spec.rb  # Run a single spec file
bundle exec rake rubocop           # Lint check
bundle exec rake spec:modernization  # Full modernization regression suite (aliases, tool-calling, MCP, JSON schema, OpenAI parity)
bundle exec rake spec:llms_live    # Live LLM provider smoke tests (requires API keys in .env)
bundle exec rake spec:minimal_dependencies  # Test with minimal gem dependencies
bundle exec rake spec:openai_client_parity  # OpenAI client migration tests
```

Default rake task runs both `spec` and `rubocop`.

## Architecture

Three core abstractions form a pipeline: **Engine → Boxcar → Train**.

### Engine (`lib/boxcars/engine.rb`)
LLM provider abstraction. Each engine wraps a specific provider API (OpenAI, Anthropic, Groq, Gemini, Cohere, Perplexity, Ollama, Together, Cerebras). Engines declare `capabilities()` (tool_calling, structured_output_json_schema, native_json_object, responses_api) and implement `client()` for API calls.

Engine implementations live in `lib/boxcars/engine/`. Most OpenAI-compatible providers share `Boxcars::OpenAIClient` (`lib/boxcars/openai_client.rb`) as a unified HTTP client.

### Boxcar (`lib/boxcars/boxcar.rb`)
A single tool: Calculator, ActiveRecord, GoogleSearch, SQL, Swagger, etc. Each boxcar implements `call(inputs:)` with declared `input_keys` and `output_keys`. Boxcar implementations are in `lib/boxcars/boxcar/`.

### Train (`lib/boxcars/train.rb`)
Orchestrator that runs a series of boxcars using an engine. Three implementations:
- **ToolTrain** (`lib/boxcars/train/tool_train.rb`) — Native tool-calling via LLM APIs (preferred)
- **ZeroShot** (`lib/boxcars/train/zero_shot.rb`) — Legacy text-based ReAct parser
- **XMLTrain** (`lib/boxcars/train/xml_train.rb`) — XML-based structured outputs

### Engine Factory (`lib/boxcars/engines.rb`)
`Boxcars::Engines.engine(model:)` creates the right engine from a model name or alias. Default model: `"gemini-2.5-flash"`. Curated aliases include `"sonnet"`, `"opus"`, `"sonar"`, `"sonar-pro"`. Many legacy aliases are deprecated (see `DEPRECATED_MODEL_ALIASES`).

### Other Key Components
- **MCP** (`lib/boxcars/mcp/`) — Model Context Protocol integration for external tool servers
- **VectorStore** (`lib/boxcars/vector_store/`) — Pgvector, Hnswlib, and in-memory backends
- **Observability** (`lib/boxcars/observability.rb`) — Event tracking with pluggable backends (PostHog, custom)

## Testing

- RSpec with VCR/WebMock for HTTP recording — cassettes in `spec/fixtures/cassettes/`
- Tests run against recorded cassettes by default; set `NO_VCR=true` for live API calls
- `spec_helper.rb` stubs all API key env vars with dummy values so tests work without real keys
- Spec files mirror the `lib/` structure under `spec/boxcars/`

## Code Style

- Rubocop with `rubocop-rspec` and `rubocop-rake` plugins
- Max line length: 130 (excluded for specs)
- Target Ruby: 3.2+
- Provider gems are optional — core has zero runtime dependencies; providers are loaded on demand via `OptionalDependency`
