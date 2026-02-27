# Upgrading Boxcars (v0.9 -> v1.0)

This guide covers the migration path for the modernization work added in v0.9 and the planned alias removals in v1.0.

## Summary

v0.9 introduces:

- Native tool-calling runtime via `Boxcars::ToolCallingTrain`
- MCP as a first-class integration path
- JSON Schema support for `JSONEngineBoxcar`
- Deprecated model alias warnings with optional strict mode

v1.0 is expected to:

- Remove deprecated model aliases
- Prefer explicit model names (with a small curated alias set)

## 1. Model Alias Migration (Do This First)

Deprecated aliases still work in v0.9, but emit one-time warnings.

### Kept curated aliases (not deprecated)

- `sonar`
- `sonar-pro`
- `sonnet`
- `opus`

### Replace deprecated aliases

- `anthropic` -> `sonnet`
- `groq` -> `llama-3.3-70b-versatile`
- `deepseek` -> `deepseek-r1-distill-llama-70b`
- `mistral` -> `mistral-saba-24b`
- `online` -> `sonar`
- `huge` -> `sonar-pro`
- `online_huge` -> `sonar-pro`
- `sonar-huge` -> `sonar-pro`
- `sonar_huge` -> `sonar-pro`
- `sonar_pro` -> `sonar-pro`
- `flash` -> `gemini-2.5-flash`
- `gemini-flash` -> `gemini-2.5-flash`
- `gemini-pro` -> `gemini-2.5-pro`
- `cerebras` -> `gpt-oss-120b`
- `qwen` -> `Qwen/Qwen2.5-VL-72B-Instruct`

### Recommended production style

Prefer explicit model names in app code:

```ruby
Boxcars::Engines.engine(model: "gpt-4o")
Boxcars::Engines.engine(model: "claude-sonnet-4-0")
Boxcars::Engines.engine(model: "gemini-2.5-flash")
Boxcars::Engines.engine(model: "sonar-pro")
```

## 2. Enable Strict Alias Mode in CI

Use this to fail builds when deprecated aliases are used.

```ruby
# config/initializers/boxcars.rb
Boxcars.configure do |config|
  config.strict_deprecated_model_aliases = ENV["CI"] == "true"
end
```

Or enforce globally in tests:

```ruby
Boxcars::Engines.strict_deprecated_aliases = true
```

## 3. Migrate ReAct/Text Trains to Native Tool Calling (Optional, Recommended)

Existing `ZeroShot` / XML trains continue to work. `ToolCallingTrain` is the opt-in modern runtime.

### Before (legacy text ReAct)

```ruby
boxcars = [Boxcars::Calculator.new, Boxcars::GoogleSearch.new]
train = Boxcars::ZeroShot.new(boxcars: boxcars, engine: Boxcars::Engines.engine(model: "gpt-4o"))
puts train.run("What is 12 * 9 and what is the weather in Austin?")
```

### After (native tool calling)

```ruby
boxcars = [Boxcars::Calculator.new, Boxcars::GoogleSearch.new]
train = Boxcars::ToolCallingTrain.new(
  boxcars: boxcars,
  engine: Boxcars::Engines.engine(model: "gpt-4o")
)
puts train.run("What is 12 * 9 and what is the weather in Austin?")
```

### Notes

- `ToolCallingTrain` requires an engine that supports native tool-calling.
- OpenAI chat models and OpenAI Responses API (`gpt-5` style) are supported by the current runtime path.

## 4. Add MCP Tools (Optional, Recommended)

You can combine local Boxcars with MCP-discovered tools.

```ruby
engine = Boxcars::Engines.engine(model: "gpt-4o")
mcp = Boxcars::MCP.stdio(
  command: "npx",
  args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
)

begin
  train = Boxcars::MCP.tool_calling_train(
    engine: engine,
    boxcars: [Boxcars::Calculator.new],
    clients: [mcp],
    client_name_prefixes: { 0 => "Filesystem" }
  )

  puts train.run("What files are in /tmp and what is 12 * 9?")
ensure
  mcp.close
end
```

## 5. Adopt JSON Schema in `JSONEngineBoxcar`

`JSONEngineBoxcar` can validate parsed JSON against a schema. On capable engines it can also use native structured-output response formats.

```ruby
schema = {
  type: "object",
  properties: {
    share_count: { type: "string" },
    confidence: { type: ["number", "null"] }
  },
  required: ["share_count"],
  additionalProperties: false
}

boxcar = Boxcars::JSONEngineBoxcar.new(
  engine: Boxcars::Engines.engine(model: "gpt-4o"),
  json_schema: schema
)

result = boxcar.run("At last count, there were 12,321,999 shares total")
puts result.inspect
```

If you want soft validation during migration:

```ruby
boxcar = Boxcars::JSONEngineBoxcar.new(json_schema: schema, json_schema_strict: false)
```

## 6. Rollout Strategy (Suggested)

1. Replace deprecated aliases in application code.
2. Enable strict alias mode in CI.
3. Migrate one workflow from `ZeroShot` to `ToolCallingTrain`.
4. Add MCP tools where they simplify app-specific integrations.
5. Add JSON Schema to `JSONEngineBoxcar` uses that need reliable structure.
6. Upgrade to v1.0 after strict mode stays green.

## 7. Known Ongoing Modernization Work

These areas are still evolving and may receive further changes before v1.0:

- OpenAI SDK migration (an internal OpenAI-compatible client factory seam is now in place)
- Additional MCP features (streaming, reconnect/recovery, resources/prompts)
- Provider pruning policy refinements beyond alias cleanup

## 8. OpenAI SDK Migration (Planned / In Progress)

For maintainers/contributors working on the SDK swap itself, see `OPENAI_SDK_MIGRATION_PLAN.md` for the adapter contract, rollout phases, and regression matrix.

Boxcars currently uses an internal OpenAI-compatible client factory to create clients for:

- OpenAI
- Groq
- Gemini (OpenAI-compatible endpoint path used by current engine)
- Ollama

This factory is the migration seam that allows Boxcars to move toward the official OpenAI Ruby SDK for OpenAI itself without forcing a simultaneous rewrite of Groq/Gemini/Ollama engine integrations.

### What users should do now

- Prefer `Boxcars::Engines.engine(...)` or engine classes directly (`Boxcars::Openai`, `Boxcars::Groq`, etc.).
- Avoid depending on the exact underlying client object class returned inside engine internals.
- Prefer explicit model names and `ToolCallingTrain` for new builds.

### OpenAI backend defaults (v0.9+)

`Boxcars::Openai` now defaults to `:official_openai`. You can still opt back to `:ruby_openai` globally, per engine, or per call:

```ruby
# global/process opt-out
# OPENAI_CLIENT_BACKEND=ruby_openai
# optional strict mode: fail unless native official wiring is available
# OPENAI_OFFICIAL_REQUIRE_NATIVE=true

engine = Boxcars::Openai.new(
  model: "gpt-4o-mini",
  openai_client_backend: :ruby_openai
)

engine.run("Write a one-line summary")

# per-call override
engine.run("Write another one-line summary", openai_client_backend: :official_openai)
```

Groq/Gemini/Ollama remain pinned to `:ruby_openai` during this migration phase.

### Notebook compatibility matrix (v0.9+)

The example notebooks under `notebooks/` were updated with an "OpenAI Backend (Migration)" setup cell so backend selection is explicit.

| Notebook | Current status | Required changes |
| --- | --- | --- |
| `notebooks/boxcars_examples.ipynb` | Uses `Boxcars::Engines`/Boxcars abstractions; follows default backend behavior. | None. |
| `notebooks/swagger_examples.ipynb` | Uses `Boxcars::Swagger`; unaffected by OpenAI backend wiring details. | None. |
| `notebooks/vector_search_examples.ipynb` | Uses `Boxcars::Openai.open_ai_client` for embeddings/vector search. Adapter path now supports embeddings in both backends. | None (keep migration setup cell if you want backend pinning). |
| `notebooks/embeddings/embeddings_example.ipynb` | Uses `Boxcars::Openai.open_ai_client` for embeddings/vector search. Adapter path now supports embeddings in both backends. | None (keep migration setup cell if you want backend pinning). |

If you enable strict native mode (`OPENAI_OFFICIAL_REQUIRE_NATIVE=true` or `config.openai_official_require_native = true`), ensure native official OpenAI SDK wiring is available; otherwise notebook runs that initialize the OpenAI client will fail early by design.

### Notebook CI cadence (recommended)

- Start with PR smoke coverage for notebook code paths that do not require live API calls.
- Add a scheduled weekly run (not nightly) for any live integration notebook checks to limit cost and flaky failures while migration work is active.
- Consider nightly only after backend defaults, SDK wiring, and cassette strategy are stable.
- If you want live checks to enforce native official wiring, set repository variables:
  - `OPENAI_OFFICIAL_REQUIRE_NATIVE=true` (Boxcars fail-fast behavior)
  - or `NOTEBOOKS_LIVE_REQUIRE_NATIVE=true` (script-level assertion)

Note: during this migration window, both SDK families use `OpenAI::Client` naming, so Boxcars keeps `ruby-openai` as the baseline for OpenAI-compatible providers and exposes the official path through the backend/builder seam. If only `ruby-openai` is loaded, Boxcars can auto-configure an official-backend compatibility builder.
When this compatibility bridge is used, Boxcars emits a one-time warning so rollout logs clearly show the runtime path.

If you want strict native behavior instead of bridge fallback:

```ruby
Boxcars.configure do |config|
  config.openai_official_require_native = true
end
```

You can also set the process default with an environment variable:

```bash
OPENAI_CLIENT_BACKEND=ruby_openai bundle exec your_command
```

When enabling `:official_openai`, you can provide a builder in config:

```ruby
Boxcars.configure do |config|
  config.openai_client_backend = :official_openai
  config.openai_official_client_builder = lambda do |access_token:, uri_base:, organization_id:, log_errors:|
    OpenAI::Client.new(
      api_key: access_token,
      base_url: uri_base,
      organization: organization_id
    )
  end
end
```

Optional startup preflight:

```ruby
Boxcars::OpenAICompatibleClient.validate_backend_configuration!
```

This preflight validates both the selected backend and the loaded `OpenAI::Client` shape, so backend/client mismatches fail early.

If you are validating migration behavior in CI or locally, run:

```bash
bundle exec rake spec:vcr_openai_smoke
bundle exec rake spec:notebooks_smoke
bundle exec rake spec:openai_backend_parity
# and forced-official subset:
bundle exec rake spec:openai_backend_parity_official
# or run the broader modernization regression suite:
bundle exec rake spec:modernization
# optional live notebook check (requires OPENAI_ACCESS_TOKEN):
bundle exec rake spec:notebooks_live
# optional native-enforced run:
OPENAI_OFFICIAL_REQUIRE_NATIVE=true bundle exec rake spec:notebooks_live
# selective cassette re-record for OpenAI/embeddings (requires network + OPENAI_ACCESS_TOKEN):
OPENAI_ACCESS_TOKEN=... bundle exec rake spec:vcr_openai_refresh
```

### What should remain stable for users during the SDK transition

- `Boxcars::Openai` public constructor and `#run` behavior
- `Boxcars::Engines.engine(model: ...)`
- `ToolCallingTrain` usage
- `JSONEngineBoxcar` usage (including `json_schema:` support)
- MCP + Boxcar composition APIs

### What may change internally (without app code changes)

- Which Ruby SDK/class is used under the hood for OpenAI requests
- OpenAI request/response normalization in `Boxcars::Openai`
- Internal observability payload extraction details (while preserving public behavior)

### If your app monkey-patches internals

If you patch or stub internals in tests, prefer stubbing:

- `Boxcars::Openai#client`
- `Boxcars::Engines.engine`
- Boxcar `#run` / `#conduct`

instead of stubbing the concrete OpenAI SDK client implementation directly.

This will make your app and tests much more resilient to the OpenAI SDK migration.
