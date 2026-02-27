# OpenAI SDK Migration Plan (Maintainers)

This document tracks the migration of Boxcars from `ruby-openai` to the official OpenAI Ruby SDK for OpenAI and OpenAI-compatible providers.

## Goals

- Keep public Boxcars APIs stable during the migration.
- Migrate OpenAI engine internals first without forcing provider rewrites.
- Preserve `ToolCallingTrain`, JSON schema support, and Responses API behavior.
- Make the migration testable behind a backend selector.

## Non-Goals (Initial Migration)

- Rewriting Groq/Gemini/Ollama engines to provider-native SDKs.
- Removing the OpenAI-compatible client seam.
- Changing public engine constructors or `Boxcars::Engines.engine(model: ...)`.

## Current Constraint

- Official SDK wiring still requires handling variations in client constructor/resource method signatures across versions.
- Backend preflight must fail fast when no official client wiring is available.

## Current State

- `/Users/francis/src/boxcars/lib/boxcars/openai_client.rb` is the canonical factory seam.
- OpenAI-compatible engines now route through the shared client factory seam.
- `:official_openai` exists behind an `official_client_builder` hook.
- If an official-style `OpenAI::Client` class is detected, the factory can auto-configure that builder.
- OpenAI-compatible providers are pinned to `:official_openai` via engine-level wiring.

## Target Architecture

Use a shared OpenAI-compatible client factory and method shim (`chat_create`, `responses_create`, etc.) so SDK method-shape differences remain isolated.

### Phase 1 (Now / Prep)

- `OpenAIClient.build(...)` constructs an official client/decorated shim.
- `:official_openai` uses an explicit builder, or auto-detects an official-style client class when available.
- If neither is available, `:official_openai` raises a clear `ConfigurationError`.

### Phase 2 (Official SDK Backend)

Implement `:official_openai` path for all OpenAI-compatible engines.

- Engines use the shared factory/decorated client, not raw SDK calls scattered across engines.

### Phase 3 (Default Switch) [Complete]

- Runtime now targets the official OpenAI client path only.

## Internal Client Contract

This contract is internal and should be tested directly.

### Constructor Inputs

- `access_token:`
- `organization_id:` (OpenAI only)
- `uri_base:` (for OpenAI-compatible providers)
- `log_errors:`

### Methods

- `chat_create(parameters:)`
- `completions_create(parameters:)`
- `responses_create(parameters:)`
- `supports_responses_api?`

### Return Type

Each method should return a Ruby `Hash` matching the shapes Boxcars already expects today:

- Chat/completions: hash with `"choices"` or `"error"`
- Responses API: hash with `"output"` or `"error"`

This keeps `Boxcars::Openai` logic mostly unchanged.

## Response Normalization Rules

Normalize official SDK responses into the same keys used by current code:

- Symbols -> string keys
- SDK object wrappers -> plain hashes/arrays
- Response text/tool calls -> current `"choices"` / `"output"` extraction paths
- Error payloads -> include `"error"` key when possible

If exact normalization is not possible, adapt in the shared client layer instead of changing multiple engines.

## Error Handling Contract

Current approach:

- Engines rescue `StandardError` and derive status codes from `http_status` or `status` when available.
- Preserve current engine error text behavior as much as practical.
- Avoid leaking SDK-specific exception assumptions into multiple engines.

## Client Wiring Rules

- Apps can provide a config-level `openai_official_client_builder` (callable)
- Optional strict mode: `openai_official_require_native=true` to fail unless native official wiring is available
- Builder precedence: module-level `OpenAIClient.official_client_builder` > config builder > auto-detected official client class
- Optional preflight check: `OpenAIClient.validate_client_configuration!`
- Preflight validates official client wiring before runtime calls

## Rollout Plan (Code)

1. Add shared client methods and route OpenAI engine through `*_create` methods.
2. Add official SDK implementation behind `:official_openai`.
3. Migrate OpenAI-compatible providers to shared client usage.
4. Remove community backend code paths.
5. Keep regression matrix (below) green on official path.

## Regression Test Matrix

Run these before migration releases:

```bash
bundle exec rake spec:openai_client_parity
bundle exec rake spec:openai_client_parity_official
# broader modernization lane:
bundle exec rake spec:modernization
```

### Unit

- `/Users/francis/src/boxcars/spec/boxcars/openai_client_spec.rb`
- Adapter-specific specs (new)
- `/Users/francis/src/boxcars/spec/boxcars/engine/capabilities_spec.rb`
- `/Users/francis/src/boxcars/spec/boxcars/tool_calling_train_spec.rb`
- `/Users/francis/src/boxcars/spec/boxcars/json_engine_boxcar_schema_spec.rb`

### Engine behavior

- `/Users/francis/src/boxcars/spec/boxcars/openai_spec.rb`

Focus on:

- Chat models
- Responses API (`gpt-5` style)
- Tool-calling loops
- Structured output (`json_schema`) request shaping for supported paths
- Error propagation

### Provider regression (must pass on `:official_openai` path)

- Groq engine specs
- Gemini-compatible engine specs
- Ollama engine specs

The SDK migration should not change their behavior.

## Compatibility Guidance for Contributors

- Keep the factory seam and backend selector (`:official_openai`) for extension points.
- Prefer shared client-level normalization over scattering SDK branching logic across engines.
- Remove legacy `ruby_openai` references from new code/docs.

## Open Questions

- Which official SDK response objects need explicit conversion for tool-call payloads?
- Is Responses API feature parity complete for Boxcars use cases?
- Do observability hooks need client-layer metadata normalization?
- Are there any remaining notebooks/examples that still imply removed backend aliases?
