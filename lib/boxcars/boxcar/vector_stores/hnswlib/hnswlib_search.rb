# frozen_string_literal: true

require 'hnswlib'
require 'json'

module Boxcars
  module VectorStores
    module Hnswlib
      class HnswlibSearch
        def initialize(vector_store:, options: {})
          validate_params(vector_store)
          @vector_store = vector_store
          @json_doc_path = options[:json_doc_path]
          @num_neighbors = options[:num_neighbors] || 1
        end

        def call(query)
          search(query)
        end

        private

        attr_reader :json_doc_path, :vector_store, :num_neighbors

        def validate_params(vector_store)
          raise_error 'vector_store must be an Hnswlib::HierarchicalNSW' unless vector_store.is_a?(::Hnswlib::HierarchicalNSW)
        end

        def search(query)
          raw_results = vector_store.search_knn(query, num_neighbors)
          raw_results.map { |doc_id, distance| lookup_embedding2(doc_id, distance) }.compact
        end

        def lookup_embedding2(doc_id, distance)
          embedding_data = parsed_data.find { |embedding| embedding[:doc_id] == doc_id }
          return unless embedding_data

          { document: embedding_data[:document], distance: distance }
        end

        def parsed_data
          @parsed_data ||= JSON.parse(
            File.read(json_doc_path),
            symbolize_names: true
          )
        end

        def raise_error(message)
          raise ::Boxcars::ArgumentError, message
        end
      end
    end
  end
end
