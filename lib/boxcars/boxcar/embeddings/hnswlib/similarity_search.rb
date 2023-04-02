# frozen_string_literal: true

require 'hnswlib'

module Boxcars
  module Embeddings
    module Hnswlib
      class SimilaritySearch
        def initialize(document_embeddings:, vector_store:, num_neighbors: 1)
          validate_params(document_embeddings, vector_store)
          @document_embeddings = document_embeddings
          @vector_store = vector_store
          @num_neighbors = num_neighbors
        end

        def call(query)
          search(query)
        end

        private

        attr_reader :document_embeddings, :vector_store, :query, :num_neighbors

        def validate_params(document_embeddings, vector_store)
          raise_error 'document_embeddings must be an array' unless document_embeddings.is_a?(Array)
          raise_error 'vector_store must be an Hnswlib::HierarchicalNSW' unless vector_store.is_a?(::Hnswlib::HierarchicalNSW)
        end

        def validate_query(query)
          raise_error 'query must be a string' unless query.is_a?(String)
          raise_error 'query must not be empty' if query.empty?
        end

        def search(query)
          raw_results = vector_store.search_knn(query, num_neighbors)
          raw_results.map { |doc_id, distance| lookup_embedding(doc_id, distance) }.compact
        end

        def lookup_embedding(doc_id, distance)
          embedding_data = document_embeddings.find { |embedding| embedding['doc_id'] == doc_id }
          return unless embedding_data

          { document: embedding_data['document'], distance: distance }
        end

        def raise_error(message)
          raise ArgumentError, message
        end
      end
    end
  end
end
