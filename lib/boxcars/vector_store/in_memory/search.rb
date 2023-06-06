# frozen_string_literal: true

module Boxcars
  module VectorStore
    module InMemory
      class Search
        include VectorStore

        # initialize the vector store InMemory::Search with the following parameters:
        # @param params [Hash] A Hash containing the initial configuration.
        # @option params [Hash] :vector_documents The vector documents to search.
        # @option params [Hash] :vector_store The vector store to search.
        def initialize(params)
          validate_params(params[:vector_documents])
          @vector_documents = params[:vector_documents]
        end

        def call(query_vector:, count: 1)
          raise ::Boxcars::ArgumentError, 'query_vector is empty' if query_vector.empty?

          search(query_vector, count)
        end

        private

        attr_reader :vector_documents

        def validate_params(vector_documents)
          return if valid_vector_store?(vector_documents)

          raise ::Boxcars::ArgumentError, "vector_documents is not valid"
        end

        def valid_vector_store?(vector_documents)
          vector_documents && vector_documents[:type] == :in_memory &&
            vector_documents[:vector_store].is_a?(Array) &&
            vector_documents[:vector_store].all? do |doc|
              doc.is_a?(Boxcars::VectorStore::Document)
            end
        end

        def search(query_vector, num_neighbors)
          results = vector_documents[:vector_store].map do |doc|
            {
              document: doc,
              similarity: cosine_similarity(query_vector, doc.embedding)
            }
          end
          results.sort_by { |result| -result[:similarity] }
                 .first(num_neighbors)
        rescue StandardError => e
          raise_argument_error("Error searching for #{query_vector}: #{e.message}")
          raise_error
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
