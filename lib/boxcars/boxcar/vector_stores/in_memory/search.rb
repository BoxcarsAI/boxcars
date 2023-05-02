# frozen_string_literal: true

# require 'openai'
#
# documents = [
#     { page_content: "hello", metadata: { a: 1 } },
#     { page_content: "hi", metadata: { a: 1 } },
#     { page_content: "bye", metadata: { a: 1 } },
#     { page_content: "what's this", metadata: { a: 1 } },
# ]
#
# vector_documents = Boxcars::VectorStores::InMemory::AddDocuments.call(embedding_tool: :openai, documents: documents)
#
# result = Boxcars::VectorStores::InMemory::Search.call(vecotr_documents: vector_documents, query: "hello")
#
# expect(result).to eq(Boxcars::VectorStores::Document.new({ page_content: "hello", metadata: { a: 1 } }))

module Boxcars
  module VectorStores
    module InMemory
      class Search
        include VectorStore
        def initialize(vector_documents:, query:, embedding_tool: :openai)
          validate_params(vector_documents, query, embedding_tool)
          @vector_documents = vector_documents
          @query = query
          @embedding_tool = embedding_tool
        end

        def call
          results = @vector_documents.map do |doc|
            {
              document: doc,
              similarity: cosine_similarity(query_vector, doc[:vector])
            }
          end
          results.min_by { |result| -result[:similarity] }[:document]
        end

        private

        def validate_params(vector_documents, query, embedding_tool)
          raise ::Boxcars::ArgumentError, 'query is empty' if query.to_s.empty?
          raise ::Boxcars::ArgumentError, 'embedding_tool is invalid' unless %i[openai tensorflow].include?(embedding_tool)

          unless vector_documents.is_a?(Array) && vector_documents.all? do |doc|
                   doc.is_a?(Hash) && doc.key?(:document) && doc.key?(:vector)
                 end
            raise ::Boxcars::ArgumentError, "vector_documents is not valid"
          end
        end

        def query_vector
          embeddings_method(@embedding_tool)[:klass].call(
            texts: [@query], client: embeddings_method(@embedding_tool)[:client]
          ).first
        end

        def embeddings_method(embedding_tool)
          case embedding_tool
          when :openai
            { klass: Boxcars::VectorStores::EmbedViaOpenAI, client: openai_client }
          when :tensorflow
            { klass: Boxcars::VectorStores::EmbedViaTensorflow, client: nil }
          end
        end

        def openai_client
          @openai_client ||= OpenAI::Client.new(access_token: ENV.fetch('OPENAI_API_KEY', nil))
        end

        def cosine_similarity(vector1, vector2)
          dot_product = vector1.zip(vector2).reduce(0) { |sum, (a, b)| sum + (a * b) }
          magnitude1 = Math.sqrt(vector1.reduce(0) { |sum, a| sum + (a**2) })
          magnitude2 = Math.sqrt(vector2.reduce(0) { |sum, b| sum + (b**2) })
          dot_product / (magnitude1 * magnitude2)
        end
      end
    end
  end
end
