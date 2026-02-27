# OpenAI SDK Migration Plan (Maintainers)

This document describes how to migrate Boxcars from `ruby-openai` to the official OpenAI Ruby SDK for OpenAI requests, while preserving the existing OpenAI-compatible integrations used by Groq, Gemini-compatible endpoints, and Ollama.

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

- `ruby-openai` and the official OpenAI Ruby SDK both expose `OpenAI::Client`, so loading both paths in one process can be ambiguous.
- During this migration window, Boxcars keeps `ruby-openai` as the provider-compatible baseline and supports the official backend via explicit builder/adapter seams.
- Backend preflight now fails fast if `:ruby_openai` is selected with a non-`ruby-openai` `OpenAI::Client` shape.

## Current State

- `/Users/francis/src/boxcars/lib/boxcars/openai_compatible_client.rb` is the factory seam.
- OpenAI/Groq/Gemini/Ollama engines all call that factory.
- `openai_client_backend` config exists, defaults to `:official_openai`.
- `:official_openai` exists behind an `official_client_builder` hook.
- If an official-style `OpenAI::Client` class is detected, the factory can auto-configure that builder.
- If only `ruby-openai` is present, the factory can auto-configure an official-backend compatibility builder.
- OpenAI-compatible providers are pinned to `:ruby_openai` and are not affected by this backend.

## Target Architecture

Use a backend-specific adapter object for OpenAI engine internals, while leaving OpenAI-compatible providers on `ruby-openai`.

### Phase 1 (Now / Prep)

- `OpenAICompatibleClient.build(..., backend:)` selects backend.
- `:ruby_openai` works.
- `:official_openai` uses an explicit builder, or auto-detects an official-style client class when available.
- If neither is available, `:official_openai` raises a clear `ConfigurationError`.

### Phase 2 (Adapter Introduction)

Introduce an internal adapter (example name):

- `Boxcars::OpenAIClientAdapter`

Responsibilities:

- Hide SDK-specific calls (`chat`, `responses`, `completions`)
- Return Boxcars-friendly normalized hashes
- Normalize errors into existing Boxcars error handling expectations

### Phase 3 (Official SDK Backend)

Implement `:official_openai` path for OpenAI engine usage only.

- OpenAI engine uses adapter, not raw SDK client methods.
- Groq/Gemini/Ollama continue using `:ruby_openai` path.

### Phase 4 (Default Switch) [Complete]

- Default `openai_client_backend` switched from `:ruby_openai` to `:official_openai`.
- Opt-out path (`:ruby_openai`) remains available for the compatibility window.
- Official backend can bridge through a compatibility builder when only `ruby-openai` is loaded.

## Proposed Adapter Contract

This contract is internal and should be tested directly.

### Constructor Inputs

- `access_token:`
- `organization_id:` (OpenAI only)
- `uri_base:` (for OpenAI-compatible providers)
- `log_errors:`
- `backend:`

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

If exact normalization is not possible, adapt in the adapter layer instead of changing multiple engines.

## Error Handling Contract

The OpenAI engine currently rescues `::OpenAI::Error` and `StandardError`.

Migration approach:

- Adapter should raise a consistent Boxcars internal error type (or `StandardError`) with `http_status` when available.
- Preserve current engine error text behavior as much as practical.
- Avoid leaking official SDK-specific exception classes outside the adapter.

## Backend Selection Rules

- Default comes from `Boxcars.configuration.openai_client_backend`
- Configuration default can be seeded by `OPENAI_CLIENT_BACKEND`
- Apps can provide a config-level `openai_official_client_builder` (callable)
- Optional strict mode: `openai_official_require_native=true` to fail instead of using ruby-openai compatibility bridge
- Builder precedence: module-level `OpenAICompatibleClient.official_client_builder` > config builder > auto-detected official client class
- Optional preflight check: `OpenAICompatibleClient.validate_backend_configuration!`
- Preflight now validates backend/client-class compatibility for both `:ruby_openai` and `:official_openai` paths
- `Boxcars::Openai` may override backend per instance/call (`openai_client_backend:`) for canary rollouts
- `backend:` argument overrides config
- Supported values during migration:
  - `:ruby_openai`
  - `:official_openai`
- Unsupported backend values raise `Boxcars::ConfigurationError`

## Rollout Plan (Code)

1. Add an adapter class with a `ruby-openai` implementation first.
2. Update `Boxcars::Openai` to call adapter methods instead of raw `client.chat`/`client.responses.create`.
3. Add an official SDK adapter implementation behind `:official_openai`.
4. Run regression matrix (below) across both backends.
5. Flip default only after parity is established.

## Regression Test Matrix

Run these before changing the default backend:

```bash
bundle exec rake spec:openai_backend_parity
bundle exec rake spec:openai_backend_parity_official
# broader modernization lane:
bundle exec rake spec:modernization
```

### Unit

- `/Users/francis/src/boxcars/spec/boxcars/openai_compatible_client_spec.rb`
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

### Provider regression (must stay on `ruby-openai`)

- Groq engine specs
- Gemini-compatible engine specs
- Ollama engine specs

The SDK migration should not change their behavior.

## Compatibility Guidance for Contributors

- Do not remove `ruby-openai` support until OpenAI provider parity is demonstrated.
- Keep the factory seam and backend selector until at least one stable release after default flip.
- Prefer adapter-level normalization over scattering SDK branching logic across engines.

## Open Questions (Track Before Default Flip)

- Which official SDK response objects need explicit conversion for tool-call payloads?
- Is Responses API feature parity complete for Boxcars use cases?
- Do observability hooks need adapter-provided metadata normalization?
- Should `:official_openai` be enabled only for `Boxcars::Openai` at first (recommended)?
