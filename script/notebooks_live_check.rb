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

embedding_model = ENV.fetch("OPENAI_EMBEDDING_MODEL", "text-embedding-3-small")

Boxcars.configure do |config|
  config.openai_access_token = token
end

openai_client = Boxcars::Openai.open_ai_client(openai_access_token: token)
runtime_mode = "official-openai-client"
log "client_class=#{openai_client.class} mode=#{runtime_mode}"

require_native = truthy_env?("NOTEBOOKS_LIVE_REQUIRE_NATIVE") || truthy_env?("OPENAI_OFFICIAL_REQUIRE_NATIVE")
if require_native
  assert!(
    openai_client.respond_to?(:responses_create) && openai_client.respond_to?(:embeddings_create),
    "Native official client methods were not available on the runtime client."
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
