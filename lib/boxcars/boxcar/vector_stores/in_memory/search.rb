# frozen_string_literal: true

# frozen_string_literal: true

# require 'openai'
#
# OpenAI.api_key = "your_api_key_here"
# openai_connection = OpenAI::Client.new
#
# documents = [
#     { page_content: "hello", metadata: { a: 1 } },
#     { page_content: "hi", metadata: { a: 1 } },
#     { page_content: "bye", metadata: { a: 1 } },
#     { page_content: "what's this", metadata: { a: 1 } },
# ]
#
# embedding = Boxcars::VectorStores::EmbedViaOpenAI.new(
#   texts: documents.map { |doc| doc[:page_content] },
#   openai_connection: openai_connection
# )
# vector_documents = Boxcars::VectorStores::InMemory::AddDocuments.new(embedding).call(documents)
#
# result = Boxcars::VectorStores::InMemory::Search.new(vector_documents).call("hello")
#
# expect(result).to eq(Boxcars::VectorStores::Document.new({ page_content: "hello", metadata: { a: 1 } }))

module Boxcars
  module VectorStores
    module InMemory
      class Search
        include VectorStore

        def initialize(vector_documents)
          validate_params(vector_documents)
          @vector_documents = vector_documents
        end

        def call(query)
          search(query)
        end

        private

        def validate_params(vector_documents)
          unless vector_documents.is_a?(Array) && vector_documents.all? { |doc| doc.is_a?(Hash) && doc.key?(:document) && doc.key?(:vector) }
            raise ::Boxcars::ArgumentError, "vector_documents must be an array of hashes with :document and :vector keys"
          end
        end

        def search(query)
          # Implement the search functionality here
          # Example: using cosine similarity
          query_vector = Boxcars::VectorStores::EmbedViaOpenAI.call(query)
          results = @vector_documents.map do |doc|
            {
              document: doc,
              similarity: cosine_similarity(query_vector, doc[:vector])
            }
          end
          results.sort_by { |result| -result[:similarity] }.first[:document]
        end

        def cosine_similarity(vector1, vector2)
          dot_product = vector1.zip(vector2).reduce(0) { |sum, (a, b)| sum + a * b }
          magnitude1 = Math.sqrt(vector1.reduce(0) { |sum, a| sum + a**2 })
          magnitude2 = Math.sqrt(vector2.reduce(0) { |sum, b| sum + b**2 })
          dot_product / (magnitude1 * magnitude2)
        end
      end
    end
  end
end
