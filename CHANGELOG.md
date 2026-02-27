# Changelog

## [Unreleased]

### Upgrade Guide (v0.9 -> v1.0 planned)

This section tracks the modernization work that is being added in v0.9 with a compatibility window before v1.0 removals.

#### New Runtime / Tooling Foundations (v0.9)

- `Boxcars::ToolCallingTrain` added for native LLM tool-calling (chat-completions and OpenAI Responses API style loops).
- Boxcars now expose normalized tool specs / JSON Schema for tool-calling APIs.
- `JSONEngineBoxcar` supports JSON Schema validation and can use native structured-output response formats on capable engines.
- MCP is a first-class integration path:
  - `Boxcars::MCP.stdio(...)` to connect to an MCP server over `stdio`
  - `Boxcars::MCP.boxcars_from_client(...)` to wrap MCP tools as Boxcars
  - `Boxcars::MCP.tool_calling_train(...)` to combine local Boxcars + MCP tools into a `ToolCallingTrain`
- OpenAI backend migration controls added:
  - `Boxcars::Openai` now runs on the official OpenAI client path only (`:ruby_openai` is unsupported)
  - `OPENAI_API_KEY` is accepted as a fallback for `OPENAI_ACCESS_TOKEN` in configuration lookup
  - `openai_official_client_builder` config hook for official client injection
  - `openai_official_require_native` toggle to fail fast unless native official wiring is available
  - Client compatibility preflight checks in `OpenAICompatibleClient.validate_client_configuration!`
  - `JSONEngineBoxcar` now keeps native JSON Schema structured-output enabled on OpenAI Responses models (maps `response_format` to Responses `text.format`)
  - OpenAI-compatible provider pinning to `:official_openai` during migration (OpenAI/Groq/Gemini/Ollama/Google/Cerebras/Together)
  - CI parity lanes via `spec:openai_client_parity` and `spec:openai_client_parity_official`
  - Minimal-dependency compatibility lane via `spec:minimal_dependencies` (isolated bundle with only `boxcars`)
  - Consolidated modernization regression lane via `spec:modernization`
  - Notebook migration setup cells added under `notebooks/` for explicit client wiring during rollout
  - Upgrade guide includes a notebook compatibility matrix for backend migration expectations
  - Notebook CI lanes added:
    - PR-safe `notebook-smoke` job via `spec:notebooks_smoke`
    - Weekly/manual live compatibility job via `spec:notebooks_live` (requires `OPENAI_ACCESS_TOKEN`)
    - Optional native-only enforcement for live notebook checks via workflow variables (`OPENAI_OFFICIAL_REQUIRE_NATIVE` or `NOTEBOOKS_LIVE_REQUIRE_NATIVE`)
  - Targeted VCR refresh tasks added for OpenAI/embeddings cassette maintenance:
    - `spec:vcr_openai_smoke`
    - `spec:vcr_openai_refresh`

#### Dependency and Runtime Migration Updates (v0.9)

- Runtime dependency upgrades:
  - ActiveRecord and ActiveSupport moved to `~> 8.1`.
  - `pgvector` updated to `~> 0.3.2`.
  - Official `openai` Ruby SDK replaces `ruby-openai` for OpenAI-compatible engine paths.
  - `vcr`, `webmock`, and `rubocop-rake` updated.
- Swagger modernization:
  - Swagger prompt/cassette/notebook guidance now uses Faraday.
  - `rest-client` removed from Boxcars runtime dependencies.
- Optionalized legacy dependencies:
  - `intelligence` removed as a hard runtime dependency.
    - `Boxcars::IntelligenceBase` remains supported and now fails with a clear setup error if the gem is missing.
  - `gpt4all` removed as a hard runtime dependency.
    - `Boxcars::Gpt4allEng` remains supported and now fails with a clear setup error if the gem is missing.
  - Provider/tooling gems are now optional at runtime (loaded on use with setup errors if missing):
    - `openai` for OpenAI and OpenAI-compatible engines (OpenAI/Groq/Gemini/Ollama/Google/Cerebras/Together)
    - `ruby-anthropic` for `Boxcars::Anthropic`
    - `google_search_results` for `Boxcars::GoogleSearch`
    - `faraday` for `Boxcars::Perplexityai` / `Boxcars::Cohere`
    - `activerecord` for `Boxcars::ActiveRecord` / `Boxcars::SQLActiveRecord` outside Rails
    - `sequel` for `Boxcars::SQLSequel`
    - `pg` + `pgvector` for pgvector-backed vector-store paths
    - `nokogiri` for XML trains and `URLText` HTML parsing
    - `hnswlib` for HNSW vector-store paths
- Provider runtime convergence:
  - `Boxcars::Google`, `Boxcars::Cerebras`, and `Boxcars::Together` migrated off `IntelligenceBase` to the OpenAI-compatible official client path.
  - OpenAI-compatible engines now pin to `:official_openai` via the client factory seam.
- Current remaining `bundle outdated` item after this pass:
  - `diff-lcs` (`2.x` blocked by RSpec 3.x dependency constraint `< 2.0`).

#### Model Alias Deprecations (warning now, planned removal in v1.0)

Deprecated aliases currently emit a one-time warning (per process) and still work in v0.9.

Recommended replacements:

- `anthropic` -> `sonnet`
- `groq` -> `llama-3.3-70b-versatile`
- `deepseek` -> `deepseek-r1-distill-llama-70b`
- `mistral` -> `mistral-saba-24b`
- `online` -> `sonar`
- `huge` / `online_huge` / `sonar_huge` / `sonar-huge` / `sonar_pro` -> `sonar-pro`
- `flash` / `gemini-flash` -> `gemini-2.5-flash`
- `gemini-pro` -> `gemini-2.5-pro`
- `cerebras` -> `gpt-oss-120b`
- `qwen` -> `Qwen/Qwen2.5-VL-72B-Instruct`

Kept curated aliases (not deprecated):

- `sonar`
- `sonar-pro`
- `sonnet`
- `opus`

#### Strict Migration Mode (recommended for CI)

To fail fast on deprecated aliases during migration testing:

```ruby
Boxcars.configure do |config|
  config.strict_deprecated_model_aliases = true
end

# or:
Boxcars::Engines.strict_deprecated_aliases = true
```

#### Planned v1.0 Direction

- Remove deprecated aliases listed above.
- Prefer explicit model names and a small curated alias set (`sonar`, `sonar-pro`, `sonnet`, `opus`).
- Continue OpenAI SDK migration behind the internal OpenAI-compatible client factory seam to reduce provider regressions.

## [v0.8.5](https://github.com/BoxcarsAI/boxcars/tree/v0.8.5) (2025-07-01)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.8.4...v0.8.5)

## [v0.8.4](https://github.com/BoxcarsAI/boxcars/tree/v0.8.4) (2025-06-10)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.8.3...v0.8.4)

**Merged pull requests:**

- add user\_id to observability context data [\#252](https://github.com/BoxcarsAI/boxcars/pull/252) ([francis](https://github.com/francis))

## [v0.8.3](https://github.com/BoxcarsAI/boxcars/tree/v0.8.3) (2025-06-09)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.8.2...v0.8.3)

## [v0.8.2](https://github.com/BoxcarsAI/boxcars/tree/v0.8.2) (2025-06-04)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.8.1...v0.8.2)

## [v0.8.1](https://github.com/BoxcarsAI/boxcars/tree/v0.8.1) (2025-06-03)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.8.0...v0.8.1)

## [v0.8.0](https://github.com/BoxcarsAI/boxcars/tree/v0.8.0) (2025-06-03)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.7.7...v0.8.0)

**Closed issues:**

- ActiveRecord translations [\#249](https://github.com/BoxcarsAI/boxcars/issues/249)
- Any chance of getting AWS Bedrock as a provider? [\#239](https://github.com/BoxcarsAI/boxcars/issues/239)

**Merged pull requests:**

- Add observability hooks [\#251](https://github.com/BoxcarsAI/boxcars/pull/251) ([francis](https://github.com/francis))

## [v0.7.7](https://github.com/BoxcarsAI/boxcars/tree/v0.7.7) (2025-04-23)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.7.6...v0.7.7)

## [v0.7.6](https://github.com/BoxcarsAI/boxcars/tree/v0.7.6) (2025-04-22)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.7.5...v0.7.6)

## [v0.7.5](https://github.com/BoxcarsAI/boxcars/tree/v0.7.5) (2025-04-21)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.7.4...v0.7.5)

**Merged pull requests:**

- Together AI Engine [\#250](https://github.com/BoxcarsAI/boxcars/pull/250) ([francis](https://github.com/francis))

## [v0.7.4](https://github.com/BoxcarsAI/boxcars/tree/v0.7.4) (2025-04-16)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.7.3...v0.7.4)

## [v0.7.3](https://github.com/BoxcarsAI/boxcars/tree/v0.7.3) (2025-01-20)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.7.2...v0.7.3)

**Merged pull requests:**

- add cerebras tests [\#246](https://github.com/BoxcarsAI/boxcars/pull/246) ([francis](https://github.com/francis))

## [v0.7.2](https://github.com/BoxcarsAI/boxcars/tree/v0.7.2) (2025-01-17)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.7.1...v0.7.2)

**Merged pull requests:**

- cerebras bug fixes [\#245](https://github.com/BoxcarsAI/boxcars/pull/245) ([francis](https://github.com/francis))

## [v0.7.1](https://github.com/BoxcarsAI/boxcars/tree/v0.7.1) (2025-01-17)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.6.9...v0.7.1)

**Merged pull requests:**

- add Cerebras [\#244](https://github.com/BoxcarsAI/boxcars/pull/244) ([francis](https://github.com/francis))
- \[infra\] Bump pg from 1.5.8 to 1.5.9 [\#231](https://github.com/BoxcarsAI/boxcars/pull/231) ([dependabot[bot]](https://github.com/apps/dependabot))

## [v0.6.9](https://github.com/BoxcarsAI/boxcars/tree/v0.6.9) (2024-12-19)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.6.8...v0.6.9)

## [v0.6.8](https://github.com/BoxcarsAI/boxcars/tree/v0.6.8) (2024-12-07)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.6.7...v0.6.8)

## [v0.6.7](https://github.com/BoxcarsAI/boxcars/tree/v0.6.7) (2024-12-04)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.6.6...v0.6.7)

## [v0.6.6](https://github.com/BoxcarsAI/boxcars/tree/v0.6.6) (2024-11-15)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.6.5...v0.6.6)

**Merged pull requests:**

- update anthropic prompt output [\#235](https://github.com/BoxcarsAI/boxcars/pull/235) ([francis](https://github.com/francis))
- \[infra\] Bump rubocop-rspec from 3.1.0 to 3.2.0 [\#230](https://github.com/BoxcarsAI/boxcars/pull/230) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump rexml from 3.3.8 to 3.3.9 [\#229](https://github.com/BoxcarsAI/boxcars/pull/229) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump activerecord from 7.1.4 to 7.1.4.2 [\#228](https://github.com/BoxcarsAI/boxcars/pull/228) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump activesupport from 7.1.4 to 7.1.4.2 [\#227](https://github.com/BoxcarsAI/boxcars/pull/227) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump rubocop from 1.66.1 to 1.67.0 [\#224](https://github.com/BoxcarsAI/boxcars/pull/224) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump ruby-openai from 7.1.0 to 7.3.1 [\#223](https://github.com/BoxcarsAI/boxcars/pull/223) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump anthropic from 0.3.0 to 0.3.2 [\#220](https://github.com/BoxcarsAI/boxcars/pull/220) ([dependabot[bot]](https://github.com/apps/dependabot))
- Dep auto [\#219](https://github.com/BoxcarsAI/boxcars/pull/219) ([francis](https://github.com/francis))
- \[infra\] Bump webmock from 3.23.1 to 3.24.0 [\#218](https://github.com/BoxcarsAI/boxcars/pull/218) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump sqlite3 from 1.7.3 to 2.0.4 [\#206](https://github.com/BoxcarsAI/boxcars/pull/206) ([dependabot[bot]](https://github.com/apps/dependabot))

## [v0.6.5](https://github.com/BoxcarsAI/boxcars/tree/v0.6.5) (2024-10-04)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.6.4...v0.6.5)

**Implemented enhancements:**

- use sample sql data in the prompts [\#11](https://github.com/BoxcarsAI/boxcars/issues/11)

**Closed issues:**

- Consider methods to prevent hallucinations and incorrect answers [\#89](https://github.com/BoxcarsAI/boxcars/issues/89)
- Fix: change SQL Boxcar to use the name of the database in the prompt [\#14](https://github.com/BoxcarsAI/boxcars/issues/14)

**Merged pull requests:**

- Update ruby [\#217](https://github.com/BoxcarsAI/boxcars/pull/217) ([francis](https://github.com/francis))
- \[infra\] Bump rubocop-rspec from 3.0.4 to 3.1.0 [\#216](https://github.com/BoxcarsAI/boxcars/pull/216) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump pg from 1.5.7 to 1.5.8 [\#214](https://github.com/BoxcarsAI/boxcars/pull/214) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump dotenv from 3.1.2 to 3.1.4 [\#213](https://github.com/BoxcarsAI/boxcars/pull/213) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump rubocop from 1.65.1 to 1.66.1 [\#212](https://github.com/BoxcarsAI/boxcars/pull/212) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump activesupport from 7.1.3.4 to 7.1.4 [\#211](https://github.com/BoxcarsAI/boxcars/pull/211) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump activerecord from 7.1.3.4 to 7.1.4 [\#210](https://github.com/BoxcarsAI/boxcars/pull/210) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump rexml from 3.3.4 to 3.3.6 [\#209](https://github.com/BoxcarsAI/boxcars/pull/209) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump vcr from 6.3.0 to 6.3.1 [\#208](https://github.com/BoxcarsAI/boxcars/pull/208) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump vcr from 6.2.0 to 6.3.0 [\#207](https://github.com/BoxcarsAI/boxcars/pull/207) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump rubocop-rspec from 3.0.3 to 3.0.4 [\#205](https://github.com/BoxcarsAI/boxcars/pull/205) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump rubocop from 1.65.0 to 1.65.1 [\#204](https://github.com/BoxcarsAI/boxcars/pull/204) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump nokogiri from 1.16.6 to 1.16.7 [\#202](https://github.com/BoxcarsAI/boxcars/pull/202) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump pg from 1.5.6 to 1.5.7 [\#201](https://github.com/BoxcarsAI/boxcars/pull/201) ([dependabot[bot]](https://github.com/apps/dependabot))

## [v0.6.4](https://github.com/BoxcarsAI/boxcars/tree/v0.6.4) (2024-07-27)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.6.3...v0.6.4)

**Merged pull requests:**

- Add Ollama Engine [\#200](https://github.com/BoxcarsAI/boxcars/pull/200) ([francis](https://github.com/francis))

## [v0.6.3](https://github.com/BoxcarsAI/boxcars/tree/v0.6.3) (2024-07-26)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.6.2...v0.6.3)

**Merged pull requests:**

- Add Groq engine [\#199](https://github.com/BoxcarsAI/boxcars/pull/199) ([francis](https://github.com/francis))

## [v0.6.2](https://github.com/BoxcarsAI/boxcars/tree/v0.6.2) (2024-07-24)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.6.1...v0.6.2)

**Merged pull requests:**

- add flag for symbolizing JSON Engine Boxcar results [\#198](https://github.com/BoxcarsAI/boxcars/pull/198) ([francis](https://github.com/francis))

## [v0.6.1](https://github.com/BoxcarsAI/boxcars/tree/v0.6.1) (2024-07-19)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.5.1...v0.6.1)

**Merged pull requests:**

- various updates with Claude 3.5 support [\#197](https://github.com/BoxcarsAI/boxcars/pull/197) ([francis](https://github.com/francis))
- \[infra\] Bump rubocop-rspec from 2.30.0 to 3.0.2 [\#195](https://github.com/BoxcarsAI/boxcars/pull/195) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump nokogiri from 1.16.5 to 1.16.6 [\#194](https://github.com/BoxcarsAI/boxcars/pull/194) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump ruby-openai from 7.0.1 to 7.1.0 [\#193](https://github.com/BoxcarsAI/boxcars/pull/193) ([dependabot[bot]](https://github.com/apps/dependabot))

## [v0.5.1](https://github.com/BoxcarsAI/boxcars/tree/v0.5.1) (2024-06-14)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.4.10...v0.5.1)

**Merged pull requests:**

- Fix `Boxcars::SecurityError` error when we have newline [\#192](https://github.com/BoxcarsAI/boxcars/pull/192) ([moustafasallam](https://github.com/moustafasallam))
- \[infra\] Bump rubocop from 1.64.0 to 1.64.1 [\#190](https://github.com/BoxcarsAI/boxcars/pull/190) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump rubocop-rspec from 2.29.1 to 2.30.0 [\#188](https://github.com/BoxcarsAI/boxcars/pull/188) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump webmock from 3.23.0 to 3.23.1 [\#186](https://github.com/BoxcarsAI/boxcars/pull/186) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump rubocop from 1.60.2 to 1.64.0 [\#183](https://github.com/BoxcarsAI/boxcars/pull/183) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump rexml from 3.2.6 to 3.2.8 [\#182](https://github.com/BoxcarsAI/boxcars/pull/182) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump nokogiri from 1.16.2 to 1.16.5 [\#181](https://github.com/BoxcarsAI/boxcars/pull/181) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump anthropic from 0.1.0 to 0.2.0 [\#180](https://github.com/BoxcarsAI/boxcars/pull/180) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump debug from 1.9.1 to 1.9.2 [\#179](https://github.com/BoxcarsAI/boxcars/pull/179) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump dotenv from 3.1.0 to 3.1.2 [\#177](https://github.com/BoxcarsAI/boxcars/pull/177) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump async from 1.31.0 to 1.32.1 [\#175](https://github.com/BoxcarsAI/boxcars/pull/175) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Update ruby-openai requirement from \>= 4.2, \< 7.0 to \>= 4.2, \< 8.0 [\#174](https://github.com/BoxcarsAI/boxcars/pull/174) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump rake from 13.1.0 to 13.2.1 [\#168](https://github.com/BoxcarsAI/boxcars/pull/168) ([dependabot[bot]](https://github.com/apps/dependabot))

## [v0.4.10](https://github.com/BoxcarsAI/boxcars/tree/v0.4.10) (2024-04-19)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.4.9...v0.4.10)

**Merged pull requests:**

- Add llms [\#169](https://github.com/BoxcarsAI/boxcars/pull/169) ([francis](https://github.com/francis))
- \[infra\] Bump pg from 1.5.5 to 1.5.6 [\#163](https://github.com/BoxcarsAI/boxcars/pull/163) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump rubocop-rspec from 2.26.1 to 2.29.1 [\#160](https://github.com/BoxcarsAI/boxcars/pull/160) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump rdoc from 6.6.2 to 6.6.3.1 [\#158](https://github.com/BoxcarsAI/boxcars/pull/158) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump dotenv from 3.0.2 to 3.1.0 [\#152](https://github.com/BoxcarsAI/boxcars/pull/152) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump webmock from 3.22.0 to 3.23.0 [\#150](https://github.com/BoxcarsAI/boxcars/pull/150) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump webmock from 3.20.0 to 3.22.0 [\#148](https://github.com/BoxcarsAI/boxcars/pull/148) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump dotenv from 2.8.1 to 3.0.2 [\#146](https://github.com/BoxcarsAI/boxcars/pull/146) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump pg from 1.5.4 to 1.5.5 [\#144](https://github.com/BoxcarsAI/boxcars/pull/144) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump webmock from 3.19.1 to 3.20.0 [\#142](https://github.com/BoxcarsAI/boxcars/pull/142) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump nokogiri from 1.16.0 to 1.16.2 [\#141](https://github.com/BoxcarsAI/boxcars/pull/141) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump rspec from 3.12.0 to 3.13.0 [\#140](https://github.com/BoxcarsAI/boxcars/pull/140) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump sqlite3 from 1.7.1 to 1.7.2 [\#139](https://github.com/BoxcarsAI/boxcars/pull/139) ([dependabot[bot]](https://github.com/apps/dependabot))

## [v0.4.9](https://github.com/BoxcarsAI/boxcars/tree/v0.4.9) (2024-01-25)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.4.8...v0.4.9)

**Merged pull requests:**

- use newest models by default from Open AI [\#138](https://github.com/BoxcarsAI/boxcars/pull/138) ([francis](https://github.com/francis))
- \[infra\] Bump sqlite3 from 1.7.0 to 1.7.1 [\#137](https://github.com/BoxcarsAI/boxcars/pull/137) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump rubocop from 1.60.0 to 1.60.2 [\#136](https://github.com/BoxcarsAI/boxcars/pull/136) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump rubocop from 1.59.0 to 1.60.0 [\#133](https://github.com/BoxcarsAI/boxcars/pull/133) ([dependabot[bot]](https://github.com/apps/dependabot))

## [v0.4.8](https://github.com/BoxcarsAI/boxcars/tree/v0.4.8) (2024-01-08)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.4.7...v0.4.8)

**Closed issues:**

- OpenBSD system example [\#124](https://github.com/BoxcarsAI/boxcars/issues/124)
- End user Struggles [\#111](https://github.com/BoxcarsAI/boxcars/issues/111)
- Add Markdown Splitter [\#96](https://github.com/BoxcarsAI/boxcars/issues/96)
- Add ability to serialize trains and boxcars [\#95](https://github.com/BoxcarsAI/boxcars/issues/95)
- VectorAnswer boxcar should support all vector stores [\#84](https://github.com/BoxcarsAI/boxcars/issues/84)
- check Chroma as a vector store [\#78](https://github.com/BoxcarsAI/boxcars/issues/78)
- Reg: User account specific / Support multi-tenancy [\#77](https://github.com/BoxcarsAI/boxcars/issues/77)
- Failed request returns a string rather than a response object [\#76](https://github.com/BoxcarsAI/boxcars/issues/76)
- Improve Google Search by parsing answer box with the engine? [\#70](https://github.com/BoxcarsAI/boxcars/issues/70)
- meta data with vector store [\#64](https://github.com/BoxcarsAI/boxcars/issues/64)
- boxcar for vector search [\#60](https://github.com/BoxcarsAI/boxcars/issues/60)
- demo rails app [\#57](https://github.com/BoxcarsAI/boxcars/issues/57)
- Language of output is fixed to English [\#52](https://github.com/BoxcarsAI/boxcars/issues/52)
- Update token counting [\#37](https://github.com/BoxcarsAI/boxcars/issues/37)

**Merged pull requests:**

- \[infra\] Bump rubocop-rspec from 2.26.0 to 2.26.1 [\#132](https://github.com/BoxcarsAI/boxcars/pull/132) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump rubocop-rspec from 2.25.0 to 2.26.0 [\#131](https://github.com/BoxcarsAI/boxcars/pull/131) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump webmock from 3.18.1 to 3.19.1 [\#130](https://github.com/BoxcarsAI/boxcars/pull/130) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump pg from 1.5.3 to 1.5.4 [\#129](https://github.com/BoxcarsAI/boxcars/pull/129) ([dependabot[bot]](https://github.com/apps/dependabot))
- test with ruby 3.3 too [\#128](https://github.com/BoxcarsAI/boxcars/pull/128) ([francis](https://github.com/francis))
- \[infra\] Bump hnswlib from 0.8.1 to 0.9.0 [\#127](https://github.com/BoxcarsAI/boxcars/pull/127) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump vcr from 6.1.0 to 6.2.0 [\#126](https://github.com/BoxcarsAI/boxcars/pull/126) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump debug from 1.9.0 to 1.9.1 [\#125](https://github.com/BoxcarsAI/boxcars/pull/125) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump nokogiri from 1.15.4 to 1.15.5 [\#123](https://github.com/BoxcarsAI/boxcars/pull/123) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump debug from 1.8.0 to 1.9.0 [\#122](https://github.com/BoxcarsAI/boxcars/pull/122) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump rubocop from 1.54.2 to 1.59.0 [\#121](https://github.com/BoxcarsAI/boxcars/pull/121) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump rubocop-rspec from 2.22.0 to 2.25.0 [\#120](https://github.com/BoxcarsAI/boxcars/pull/120) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Update ruby-openai requirement from ~\> 4.2 to \>= 4.2, \< 7.0 [\#119](https://github.com/BoxcarsAI/boxcars/pull/119) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump pgvector from 0.2.1 to 0.2.2 [\#118](https://github.com/BoxcarsAI/boxcars/pull/118) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump rake from 13.0.6 to 13.1.0 [\#117](https://github.com/BoxcarsAI/boxcars/pull/117) ([dependabot[bot]](https://github.com/apps/dependabot))
- \[infra\] Bump sqlite3 from 1.6.3 to 1.6.9 [\#115](https://github.com/BoxcarsAI/boxcars/pull/115) ([dependabot[bot]](https://github.com/apps/dependabot))
- Create dependabot.yml [\#114](https://github.com/BoxcarsAI/boxcars/pull/114) ([francis](https://github.com/francis))
- Bump activesupport from 7.0.6 to 7.0.7.1 [\#113](https://github.com/BoxcarsAI/boxcars/pull/113) ([dependabot[bot]](https://github.com/apps/dependabot))
- Bump protocol-http1 from 0.15.0 to 0.16.0 [\#112](https://github.com/BoxcarsAI/boxcars/pull/112) ([dependabot[bot]](https://github.com/apps/dependabot))

## [v0.4.7](https://github.com/BoxcarsAI/boxcars/tree/v0.4.7) (2023-11-07)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.4.6...v0.4.7)

## [v0.4.6](https://github.com/BoxcarsAI/boxcars/tree/v0.4.6) (2023-11-06)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.4.5...v0.4.6)

**Merged pull requests:**

- Perpexity API [\#110](https://github.com/BoxcarsAI/boxcars/pull/110) ([francis](https://github.com/francis))

## [v0.4.5](https://github.com/BoxcarsAI/boxcars/tree/v0.4.5) (2023-10-06)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.4.4...v0.4.5)

**Merged pull requests:**

- Json engine [\#109](https://github.com/BoxcarsAI/boxcars/pull/109) ([francis](https://github.com/francis))

## [v0.4.4](https://github.com/BoxcarsAI/boxcars/tree/v0.4.4) (2023-10-03)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.4.3...v0.4.4)

## [v0.4.3](https://github.com/BoxcarsAI/boxcars/tree/v0.4.3) (2023-09-19)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.4.2...v0.4.3)

## [v0.4.2](https://github.com/BoxcarsAI/boxcars/tree/v0.4.2) (2023-08-05)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.4.1...v0.4.2)

**Merged pull requests:**

- Add xml engine boxcar [\#108](https://github.com/BoxcarsAI/boxcars/pull/108) ([francis](https://github.com/francis))
- Updated README.md [\#107](https://github.com/BoxcarsAI/boxcars/pull/107) ([Flummoxsoftly](https://github.com/Flummoxsoftly))

## [v0.4.1](https://github.com/BoxcarsAI/boxcars/tree/v0.4.1) (2023-07-25)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.4.0...v0.4.1)

**Merged pull requests:**

- Do not use the engine\_prefix to start the LLM prompt for the XML Train [\#106](https://github.com/BoxcarsAI/boxcars/pull/106) ([francis](https://github.com/francis))
- Adding 16k context [\#105](https://github.com/BoxcarsAI/boxcars/pull/105) ([eltoob](https://github.com/eltoob))

## [v0.4.0](https://github.com/BoxcarsAI/boxcars/tree/v0.4.0) (2023-07-19)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.3.5...v0.4.0)

**Closed issues:**

- Add Anthropic Engine [\#103](https://github.com/BoxcarsAI/boxcars/issues/103)

**Merged pull requests:**

- Add Anthropic Engine - closes \#103 [\#104](https://github.com/BoxcarsAI/boxcars/pull/104) ([francis](https://github.com/francis))

## [v0.3.5](https://github.com/BoxcarsAI/boxcars/tree/v0.3.5) (2023-07-13)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.3.4...v0.3.5)

## [v0.3.4](https://github.com/BoxcarsAI/boxcars/tree/v0.3.4) (2023-07-11)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.3.3...v0.3.4)

## [v0.3.3](https://github.com/BoxcarsAI/boxcars/tree/v0.3.3) (2023-07-10)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.3.2...v0.3.3)

## [v0.3.2](https://github.com/BoxcarsAI/boxcars/tree/v0.3.2) (2023-07-10)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.3.1...v0.3.2)

**Merged pull requests:**

- add XML Train and XML Zero Shot [\#102](https://github.com/BoxcarsAI/boxcars/pull/102) ([francis](https://github.com/francis))

## [v0.3.1](https://github.com/BoxcarsAI/boxcars/tree/v0.3.1) (2023-07-01)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.16...v0.3.1)

**Closed issues:**

- Add a running log of prompts for debugging [\#99](https://github.com/BoxcarsAI/boxcars/issues/99)
- Anyway to create conversation? [\#73](https://github.com/BoxcarsAI/boxcars/issues/73)

**Merged pull requests:**

- now, when you call run on a train multiple times, it remembers the ru… [\#101](https://github.com/BoxcarsAI/boxcars/pull/101) ([francis](https://github.com/francis))

## [v0.2.16](https://github.com/BoxcarsAI/boxcars/tree/v0.2.16) (2023-06-26)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.15...v0.2.16)

**Implemented enhancements:**

- Support Sequel connection type [\#22](https://github.com/BoxcarsAI/boxcars/issues/22)

**Closed issues:**

- Using the SQL model This model's maximum context length is 4097 tokens [\#88](https://github.com/BoxcarsAI/boxcars/issues/88)

**Merged pull requests:**

- Add running logs [\#100](https://github.com/BoxcarsAI/boxcars/pull/100) ([francis](https://github.com/francis))
- create new Sequel boxcar, and refactor Active Record SQL boxcar [\#98](https://github.com/BoxcarsAI/boxcars/pull/98) ([francis](https://github.com/francis))
- Support for Sequel SQL connection types [\#97](https://github.com/BoxcarsAI/boxcars/pull/97) ([eltoob](https://github.com/eltoob))

## [v0.2.15](https://github.com/BoxcarsAI/boxcars/tree/v0.2.15) (2023-06-09)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.14...v0.2.15)

**Merged pull requests:**

- make suggested next actions optional [\#94](https://github.com/BoxcarsAI/boxcars/pull/94) ([francis](https://github.com/francis))

## [v0.2.14](https://github.com/BoxcarsAI/boxcars/tree/v0.2.14) (2023-06-06)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.13...v0.2.14)

**Closed issues:**

- VectorAnswer always return error "Query must a string" [\#90](https://github.com/BoxcarsAI/boxcars/issues/90)
- Readme vector search example 404 [\#86](https://github.com/BoxcarsAI/boxcars/issues/86)
- Add Boxcar similar to LLMChain [\#85](https://github.com/BoxcarsAI/boxcars/issues/85)

**Merged pull requests:**

- Chore/refactored vector stores [\#92](https://github.com/BoxcarsAI/boxcars/pull/92) ([jaigouk](https://github.com/jaigouk))
- Fix the issue of calling the wrong method in vector\_answer.rb. [\#91](https://github.com/BoxcarsAI/boxcars/pull/91) ([xleotranx](https://github.com/xleotranx))
- issue\_83 Fix readme 404 [\#87](https://github.com/BoxcarsAI/boxcars/pull/87) ([ntabernacle](https://github.com/ntabernacle))

## [v0.2.13](https://github.com/BoxcarsAI/boxcars/tree/v0.2.13) (2023-05-24)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.12...v0.2.13)

**Closed issues:**

- Typo "Boscar.error" should be "Boxcars.error" [\#82](https://github.com/BoxcarsAI/boxcars/issues/82)

**Merged pull requests:**

- Add vector answer boxcar [\#79](https://github.com/BoxcarsAI/boxcars/pull/79) ([francis](https://github.com/francis))

## [v0.2.12](https://github.com/BoxcarsAI/boxcars/tree/v0.2.12) (2023-05-22)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.11...v0.2.12)

**Closed issues:**

- GPT-4 support? [\#71](https://github.com/BoxcarsAI/boxcars/issues/71)
- add PgVector Vector Store [\#68](https://github.com/BoxcarsAI/boxcars/issues/68)

**Merged pull requests:**

- issue\_82 typo "Boscar" instead of "Boxcars" [\#83](https://github.com/BoxcarsAI/boxcars/pull/83) ([MadBomber](https://github.com/MadBomber))
- Update boxcars.rb config example [\#81](https://github.com/BoxcarsAI/boxcars/pull/81) ([nhorton](https://github.com/nhorton))
- Feature- added pgvector vector store [\#80](https://github.com/BoxcarsAI/boxcars/pull/80) ([jaigouk](https://github.com/jaigouk))
- drop support for pre ruby 3 version [\#75](https://github.com/BoxcarsAI/boxcars/pull/75) ([francis](https://github.com/francis))
- Chore - refine VectorSearch [\#74](https://github.com/BoxcarsAI/boxcars/pull/74) ([jaigouk](https://github.com/jaigouk))
- raise error if OpenAI API returns error or nil. closes \#71 [\#72](https://github.com/BoxcarsAI/boxcars/pull/72) ([francis](https://github.com/francis))

## [v0.2.11](https://github.com/BoxcarsAI/boxcars/tree/v0.2.11) (2023-05-05)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.10...v0.2.11)

**Closed issues:**

- Chore: move vector store to top level [\#67](https://github.com/BoxcarsAI/boxcars/issues/67)

**Merged pull requests:**

- Move vector store [\#69](https://github.com/BoxcarsAI/boxcars/pull/69) ([francis](https://github.com/francis))

## [v0.2.10](https://github.com/BoxcarsAI/boxcars/tree/v0.2.10) (2023-05-05)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.9...v0.2.10)

**Implemented enhancements:**

- Notion Q&A [\#13](https://github.com/BoxcarsAI/boxcars/issues/13)

**Closed issues:**

- undefined method `default\_train' for Boxcars:Module \(ActiveRecord example\) [\#66](https://github.com/BoxcarsAI/boxcars/issues/66)
- Chore: reduce the number of markdown files in Notion DB folder [\#56](https://github.com/BoxcarsAI/boxcars/issues/56)

**Merged pull requests:**

- \[DRAFT\] Feature - add in memory vector store [\#65](https://github.com/BoxcarsAI/boxcars/pull/65) ([jaigouk](https://github.com/jaigouk))
- Chore - rename module name from Embeddings to VectorStores [\#63](https://github.com/BoxcarsAI/boxcars/pull/63) ([jaigouk](https://github.com/jaigouk))
- remove bunch of markdown files in Notion\_DB directory [\#62](https://github.com/BoxcarsAI/boxcars/pull/62) ([jaigouk](https://github.com/jaigouk))
- Fixed typo in README.md [\#61](https://github.com/BoxcarsAI/boxcars/pull/61) ([robmack](https://github.com/robmack))

## [v0.2.9](https://github.com/BoxcarsAI/boxcars/tree/v0.2.9) (2023-04-22)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.8...v0.2.9)

**Closed issues:**

- Getting started docs out of date [\#58](https://github.com/BoxcarsAI/boxcars/issues/58)

**Merged pull requests:**

- add default openai client, and new notebook [\#59](https://github.com/BoxcarsAI/boxcars/pull/59) ([francis](https://github.com/francis))

## [v0.2.8](https://github.com/BoxcarsAI/boxcars/tree/v0.2.8) (2023-04-19)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.7...v0.2.8)

**Closed issues:**

- Getting the same verbosity as in the examples [\#54](https://github.com/BoxcarsAI/boxcars/issues/54)

**Merged pull requests:**

- Add Engine for Gpt4all [\#55](https://github.com/BoxcarsAI/boxcars/pull/55) ([francis](https://github.com/francis))
- update google search to return URL for result if present [\#53](https://github.com/BoxcarsAI/boxcars/pull/53) ([francis](https://github.com/francis))
- Draft: added gpt4all [\#49](https://github.com/BoxcarsAI/boxcars/pull/49) ([jaigouk](https://github.com/jaigouk))
- Embeddings with hnswlib [\#48](https://github.com/BoxcarsAI/boxcars/pull/48) ([jaigouk](https://github.com/jaigouk))

## [v0.2.7](https://github.com/BoxcarsAI/boxcars/tree/v0.2.7) (2023-04-13)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.5...v0.2.7)

**Closed issues:**

- The class name in the sample code of BoxCar-Google-Search wiki has not been changed. [\#50](https://github.com/BoxcarsAI/boxcars/issues/50)

**Merged pull requests:**

- Add Swagger Boxcar [\#51](https://github.com/BoxcarsAI/boxcars/pull/51) ([francis](https://github.com/francis))
- Boxcars::SQL tables and except\_tables [\#47](https://github.com/BoxcarsAI/boxcars/pull/47) ([arihh](https://github.com/arihh))
- ActiveRecord updates and new Wikipedia Search boxcar [\#46](https://github.com/BoxcarsAI/boxcars/pull/46) ([francis](https://github.com/francis))
- Fix README.md log\_prompts settings [\#45](https://github.com/BoxcarsAI/boxcars/pull/45) ([arihh](https://github.com/arihh))
- Update README.md to use the GoogleSearch Boxcar [\#44](https://github.com/BoxcarsAI/boxcars/pull/44) ([stockandawe](https://github.com/stockandawe))

## [v0.2.5](https://github.com/BoxcarsAI/boxcars/tree/v0.2.5) (2023-03-30)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.4...v0.2.5)

**Merged pull requests:**

- switch to safe level 4 for eval, and rerun tests [\#43](https://github.com/BoxcarsAI/boxcars/pull/43) ([francis](https://github.com/francis))

## [v0.2.4](https://github.com/BoxcarsAI/boxcars/tree/v0.2.4) (2023-03-28)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.3...v0.2.4)

**Closed issues:**

- security [\#40](https://github.com/BoxcarsAI/boxcars/issues/40)

**Merged pull requests:**

- Fix regex action input [\#41](https://github.com/BoxcarsAI/boxcars/pull/41) ([makevoid](https://github.com/makevoid))

## [v0.2.3](https://github.com/BoxcarsAI/boxcars/tree/v0.2.3) (2023-03-20)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.2...v0.2.3)

**Merged pull requests:**

- better error handling and retry for Active Record Boxcar [\#39](https://github.com/BoxcarsAI/boxcars/pull/39) ([francis](https://github.com/francis))

## [v0.2.2](https://github.com/BoxcarsAI/boxcars/tree/v0.2.2) (2023-03-16)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.1...v0.2.2)

**Implemented enhancements:**

- return a structure from boxcars instead of just a string [\#31](https://github.com/BoxcarsAI/boxcars/issues/31)
- modify SQL boxcar to take a list of Tables. Handy if you have a large database with many tables. [\#19](https://github.com/BoxcarsAI/boxcars/issues/19)

**Closed issues:**

- make a new type of prompt that uses conversations [\#38](https://github.com/BoxcarsAI/boxcars/issues/38)
- Add test coverage [\#8](https://github.com/BoxcarsAI/boxcars/issues/8)

## [v0.2.1](https://github.com/BoxcarsAI/boxcars/tree/v0.2.1) (2023-03-08)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.0...v0.2.1)

**Implemented enhancements:**

- add the ability to use the ChatGPT API - a ChatGPT Boxcar::Engine [\#32](https://github.com/BoxcarsAI/boxcars/issues/32)
- Prompt simplification [\#29](https://github.com/BoxcarsAI/boxcars/issues/29)

**Merged pull requests:**

- use structured results internally and bring SQL up to parity with ActiveRecord boxcar. [\#36](https://github.com/BoxcarsAI/boxcars/pull/36) ([francis](https://github.com/francis))

## [v0.2.0](https://github.com/BoxcarsAI/boxcars/tree/v0.2.0) (2023-03-07)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.1.8...v0.2.0)

**Merged pull requests:**

- Default to chatgpt [\#35](https://github.com/BoxcarsAI/boxcars/pull/35) ([francis](https://github.com/francis))

## [v0.1.8](https://github.com/BoxcarsAI/boxcars/tree/v0.1.8) (2023-03-02)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.1.7...v0.1.8)

**Merged pull requests:**

- return JSON from the Active Record boxcar [\#34](https://github.com/BoxcarsAI/boxcars/pull/34) ([francis](https://github.com/francis))
- validate return values from Open AI API [\#33](https://github.com/BoxcarsAI/boxcars/pull/33) ([francis](https://github.com/francis))
- simplify prompting and parameters used. refs \#29 [\#30](https://github.com/BoxcarsAI/boxcars/pull/30) ([francis](https://github.com/francis))
- \[infra\] Added sample .env file and updated the lookup to save the key [\#27](https://github.com/BoxcarsAI/boxcars/pull/27) ([AKovtunov](https://github.com/AKovtunov))

## [v0.1.7](https://github.com/BoxcarsAI/boxcars/tree/v0.1.7) (2023-02-27)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.1.6...v0.1.7)

**Implemented enhancements:**

- figure out logging [\#10](https://github.com/BoxcarsAI/boxcars/issues/10)

**Merged pull requests:**

- Fix typos in README concepts [\#26](https://github.com/BoxcarsAI/boxcars/pull/26) ([MasterOdin](https://github.com/MasterOdin))

## [v0.1.6](https://github.com/BoxcarsAI/boxcars/tree/v0.1.6) (2023-02-24)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.1.5...v0.1.6)

**Implemented enhancements:**

- Add a callback function for Boxcars::ActiveRecord to approve changes  [\#24](https://github.com/BoxcarsAI/boxcars/issues/24)

**Merged pull requests:**

- Add approval callback function for Boxcars::ActiveRecord for changes to the data [\#25](https://github.com/BoxcarsAI/boxcars/pull/25) ([francis](https://github.com/francis))
- \[fix\] Fixed specs which required a key [\#23](https://github.com/BoxcarsAI/boxcars/pull/23) ([AKovtunov](https://github.com/AKovtunov))

## [v0.1.5](https://github.com/BoxcarsAI/boxcars/tree/v0.1.5) (2023-02-22)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.1.4...v0.1.5)

**Implemented enhancements:**

- Make Boxcars::ActiveRecord read\_only by default [\#20](https://github.com/BoxcarsAI/boxcars/issues/20)

**Merged pull requests:**

- Active Record readonly [\#21](https://github.com/BoxcarsAI/boxcars/pull/21) ([francis](https://github.com/francis))

## [v0.1.4](https://github.com/BoxcarsAI/boxcars/tree/v0.1.4) (2023-02-22)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.1.3...v0.1.4)

**Implemented enhancements:**

- Extend Sql concept to produce and run ActiveRecord code instead of SQL [\#9](https://github.com/BoxcarsAI/boxcars/issues/9)

**Merged pull requests:**

- first pass at an ActiveRecord boxcar [\#18](https://github.com/BoxcarsAI/boxcars/pull/18) ([francis](https://github.com/francis))
- change Boxcars::default\_train to Boxcars::train to improve code reada… [\#17](https://github.com/BoxcarsAI/boxcars/pull/17) ([francis](https://github.com/francis))
- rename class Serp to GoogleSearch [\#16](https://github.com/BoxcarsAI/boxcars/pull/16) ([francis](https://github.com/francis))
- Update README.md [\#15](https://github.com/BoxcarsAI/boxcars/pull/15) ([tabrez-syed](https://github.com/tabrez-syed))

## [v0.1.3](https://github.com/BoxcarsAI/boxcars/tree/v0.1.3) (2023-02-17)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.1.2...v0.1.3)

**Closed issues:**

- generate changelog automatically [\#12](https://github.com/BoxcarsAI/boxcars/issues/12)
- Make sure the yard docs are up to date and have coverage [\#7](https://github.com/BoxcarsAI/boxcars/issues/7)
- Name changes and code movement. [\#6](https://github.com/BoxcarsAI/boxcars/issues/6)
- Specs need environment variables to be set to run green [\#4](https://github.com/BoxcarsAI/boxcars/issues/4)

**Merged pull requests:**

- Get GitHub Actions to green [\#5](https://github.com/BoxcarsAI/boxcars/pull/5) ([petergoldstein](https://github.com/petergoldstein))
- Fix typo introduced by merge.  Pull publish-rubygem into its own job [\#3](https://github.com/BoxcarsAI/boxcars/pull/3) ([petergoldstein](https://github.com/petergoldstein))

## [v0.1.2](https://github.com/BoxcarsAI/boxcars/tree/v0.1.2) (2023-02-17)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.1.1...v0.1.2)

**Merged pull requests:**

- Run GitHub Actions against multiple Rubies [\#2](https://github.com/BoxcarsAI/boxcars/pull/2) ([petergoldstein](https://github.com/petergoldstein))
- \[infra\] Added deployment step for the RubyGems [\#1](https://github.com/BoxcarsAI/boxcars/pull/1) ([AKovtunov](https://github.com/AKovtunov))

## [v0.1.1](https://github.com/BoxcarsAI/boxcars/tree/v0.1.1) (2023-02-16)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.1.0...v0.1.1)

## [v0.1.0](https://github.com/BoxcarsAI/boxcars/tree/v0.1.0) (2023-02-15)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/e3c50bdc76f71c6d2abb012c38174633a5847028...v0.1.0)



\* *This Changelog was automatically generated by [github_changelog_generator](https://github.com/github-changelog-generator/github-changelog-generator)*
