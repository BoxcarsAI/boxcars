# frozen_string_literal: true

require 'hnswlib'
require 'json'

module Boxcars
  module VectorStores
    # This class is responsible for initializing the in memory vector store.
    #
    class InitializeMemoryStore
      include VectorStore

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

    end
  end
end
