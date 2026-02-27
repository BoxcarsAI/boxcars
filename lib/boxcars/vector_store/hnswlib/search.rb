# frozen_string_literal: true
require 'json'

module Boxcars
  module VectorStore
    module Hnswlib
      class Search
        include VectorStore

        # initialize the vector store search with the following parameters:
        # @param params [Hash] A Hash containing the initial configuration.
        # example:
        # {
        #   type: :hnswlib,
        #   vector_store: [
        #     Boxcars::VectorStore::Document.new(
        #       content: "hello",
        #       embedding: [0.1, 0.2, 0.3],
        #       metadata: { a: 1 }
        #     )
        #   ]
        # }
        def initialize(params)
          @vector_store = validate_params(params[:vector_documents])
          @metadata, @index_file = validate_files(vector_store)
          @search_index = load_index(metadata, index_file)
        end

        # @param query_vector [Array] The query vector to search for.
        # @param count [Integer] The number of results to return.
        # @return [Array] array of hashes with :document and :distance keys
        def call(query_vector:, count: 1)
          search(query_vector, count)
        end

        private

        attr_reader :vector_store, :index_file, :search_index, :metadata

        def validate_params(vector_documents)
          raise_argument_error('vector_documents is nil') unless vector_documents
          raise_arugment_error('vector_documents must be a hash') unless vector_documents.is_a?(Hash)
          raise_arugment_error('type must be hnswlib') unless vector_documents[:type] == :hnswlib
          raise_arugment_error('vector_store is nil') unless vector_documents[:vector_store]
          raise_arugment_error('vector_store must be an array') unless vector_documents[:vector_store].is_a?(Array)

          unless vector_documents[:vector_store].all? { |doc| doc.is_a?(Document) }
            raise_arugment_error('vector_store must be an array of Document objects')
          end

          vector_documents[:vector_store]
        end

        def validate_files(vector_store)
          metadata = vector_store.first.metadata
          raise_arugment_error('metadata must be a hash') unless metadata.is_a?(Hash)
          raise_arugment_error('metadata is empty') if metadata.empty?

          validate_string(metadata[:index_file_path], "index_file_path")
          validate_string(metadata[:json_doc_file_path], "json_doc_file_path")

          base_dir = metadata[:base_dir_path]
          index_file_file_path = metadata[:index_file_path]
          index_file =
            if !index_file_file_path.to_s.empty? && File.exist?(index_file_file_path)
              index_file_file_path
            else
              File.join(base_dir.to_s, index_file_file_path.to_s)
            end

          raise_argument_error('index_file does not exist') unless File.exist?(index_file)

          [metadata, index_file]
        end

        def load_index(metadata, index_file)
          Boxcars::OptionalDependency.require!("hnswlib", feature: "Boxcars::VectorStore::Hnswlib")
          search_index = ::Hnswlib::HierarchicalNSW.new(
            space: metadata[:metric],
            dim: metadata[:dim]
          )
          search_index.load_index(index_file)
          search_index
        end

        def search(query_vector, num_neighbors)
          raw_results = search_index.search_knn(query_vector, num_neighbors)

          raw_results.map { |doc_id, distance| lookup_embedding(doc_id, distance) }
                     .compact
                     .first(num_neighbors)
                     .sort_by { |result| result[:distance] }
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
