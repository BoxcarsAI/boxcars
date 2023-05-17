# frozen_string_literal: true

require 'hnswlib'
require 'json'

module Boxcars
  module VectorStore
    module Hnswlib
      class Search
        include VectorStore

        def initialize(params)
          validate_params(params[:vector_documents])
          @vector_documents = params[:vector_documents]
          @search_index = load_index(params[:vector_documents])
        end

        def call(query_vector:, count: 1)
          search(query_vector, count)
        end

        private

        attr_reader :vector_documents, :vector_store, :json_doc, :search_index, :metadata

        def validate_params(vector_documents)
          raise_argument_error('vector_documents is nil') unless vector_documents
          raise_arugment_error('vector_documents must be a hash') unless vector_documents.is_a?(Hash)
          raise_arugment_error('type must be hnswlib') unless vector_documents[:type] == :hnswlib
          raise_arugment_error('vector_store is nil') unless vector_documents[:vector_store]
          raise_arugment_error('vector_store must be an array') unless vector_documents[:vector_store].is_a?(Array)

          unless vector_documents[:vector_store].all? { |doc| doc.is_a?(Document) }
            raise_arugment_error('vector_store must be an array of Document objects')
          end

          true
        end

        def load_index(vector_documents)
          @metadata = vector_documents[:vector_store].first.metadata
          @json_doc = @metadata[:json_doc_file_path]

          search_index = ::Hnswlib::HierarchicalNSW.new(
            space: metadata[:metric],
            dim: metadata[:dim]
          )
          search_index.load_index(metadata[:index_file_path])
          @search_index = search_index
          @vector_store = vector_documents[:vector_store]

          search_index
        end

        def search(query_vector, num_neighbors)
          raw_results = search_index.search_knn(query_vector, num_neighbors)
          raw_results.map { |doc_id, distance| lookup_embedding(doc_id, distance) }.compact
        rescue StandardError => e
          raise_argument_error("Error searching for #{query_vector}: #{e.message}")
        end

        def lookup_embedding(doc_id, distance)
          return unless vector_store[doc_id]

          { document: vector_store[doc_id], distance: distance }
        end
      end
    end
  end
end
