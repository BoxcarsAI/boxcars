#!/usr/bin/env ruby
# frozen_string_literal: true

require "boxcars"

def log(msg)
  puts "[notebooks-live] #{msg}"
end

def assert!(condition, message)
  raise StandardError, message unless condition
end

def truthy_env?(name)
  value = ENV.fetch(name, "").to_s.strip.downcase
  %w[1 true yes y on].include?(value)
end

token = ENV.fetch("OPENAI_ACCESS_TOKEN", "").to_s.strip
raise "OPENAI_ACCESS_TOKEN is required for notebook live checks" if token.empty?

backend = ENV.fetch("OPENAI_CLIENT_BACKEND", "official_openai").to_sym
embedding_model = ENV.fetch("OPENAI_EMBEDDING_MODEL", "text-embedding-3-small")

Boxcars.configure do |config|
  config.openai_access_token = token
  config.openai_client_backend = backend
end

log "backend=#{backend}"
openai_client = Boxcars::Openai.open_ai_client(openai_access_token: token, backend: backend)
raw_client = openai_client.respond_to?(:raw_client) ? openai_client.raw_client : openai_client

bridge_mode =
  if Boxcars::OpenAICompatibleClient.send(:official_client_class?, raw_client.class)
    false
  else
    Boxcars::OpenAICompatibleClient.send(:ruby_openai_client_class?, raw_client.class)
  end

runtime_mode = bridge_mode ? "ruby-openai-compatibility-bridge" : "native-official-or-custom-builder"
log "client_class=#{raw_client.class} mode=#{runtime_mode}"

require_native = truthy_env?("NOTEBOOKS_LIVE_REQUIRE_NATIVE") || truthy_env?("OPENAI_OFFICIAL_REQUIRE_NATIVE")
if require_native
  assert!(
    !bridge_mode,
    "Native official client required, but runtime used ruby-openai compatibility bridge. " \
    "Configure an official client builder or install/use native official SDK wiring."
  )
end

embedding_payload = Boxcars::VectorStore::EmbedViaOpenAI.call(
  texts: ["Boxcars notebook live check"],
  client: openai_client,
  model: embedding_model
)
embedding = embedding_payload.first[:embedding]
assert!(embedding.is_a?(Array) && !embedding.empty?, "Expected non-empty embedding vector")
log "embedding_dim=#{embedding.length}"

input_array = [
  { content: "hello from boxcars notebooks", metadata: { source: :live_check } },
  { content: "bye from boxcars notebooks", metadata: { source: :live_check } }
]

store = Boxcars::VectorStore::InMemory::BuildFromArray.call(
  embedding_tool: :openai,
  input_array: input_array
)
search = Boxcars::VectorSearch.new(
  type: :in_memory,
  vector_documents: store,
  openai_connection: openai_client
)
results = search.call(query: "hello", count: 1)
top_content = results.first&.dig(:document)&.content
assert!(top_content.is_a?(String) && !top_content.empty?, "Expected in-memory vector search result content")
log "top_result=#{top_content.inspect}"

log "Notebook live checks passed"
