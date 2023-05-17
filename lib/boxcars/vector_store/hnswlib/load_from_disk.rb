# frozen_string_literal: true

require 'fileutils'
require 'hnswlib'
require 'json'

module Boxcars
  module VectorStore
    module Hnswlib
      class LoadFromDisk
        include VectorStore

        def initialize(params)
          validate_params(params[:index_file_path], params[:json_doc_file_path])

          @index_file_path = File.absolute_path(params[:index_file_path])
          @json_doc_file_path = File.absolute_path(params[:json_doc_file_path])
        end

        def call
          vectors = parse_json_file(json_doc_file_path)
          hnsw_vectors = load_as_hnsw_vectors(vectors)

          {
            type: :hnswlib,
            vector_store: hnsw_vectors
          }
        end

        private

        attr_reader :index_file_path, :json_doc_file_path

        def validate_params(index_file_path, json_doc_file_path)
          raise_argument_error("index_file_path must be a string") unless index_file_path.is_a?(String)
          raise_argument_error("json_doc_file_path must be a string") unless json_doc_file_path.is_a?(String)

          raise_argument_error("index_file_path must exist") unless File.exist?(index_file_path)
          raise_argument_error("json_doc_file_path must exist") unless File.exist?(json_doc_file_path)
        end

        def load_as_hnsw_vectors(vectors)
          hnsw_vectors = []
          vectors.each do |vector|
            hnsw_vector = Document.new(
              content: vector[:document],
              embedding: vector[:embedding],
              metadata: vector[:metadata]
            )
            hnsw_vectors[vectors.first[:doc_id].to_i] = hnsw_vector
          end
          hnsw_vectors
        end
      end
    end
  end
end
