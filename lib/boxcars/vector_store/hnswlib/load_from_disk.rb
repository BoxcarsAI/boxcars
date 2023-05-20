# frozen_string_literal: true

require 'fileutils'
require 'hnswlib'
require 'json'

module Boxcars
  module VectorStore
    module Hnswlib
      class LoadFromDisk
        include VectorStore

        # params:
        # base_dir_path: string (absolute path to the directory containing the index_file_path and json_doc_file_path),
        # index_file_path: string (relative path to the index file from the base_dir_path),
        # json_doc_file_path: string (relative path to the json file from the base_dir_path)
        def initialize(params)
          @base_dir_path, @index_file_path, @json_doc_file_path =
            validate_params(params)
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

        attr_reader :base_dir_path, :index_file_path, :json_doc_file_path

        def validate_params(params)
          base_dir_path = params[:base_dir_path]
          index_file_path = remove_relative_path(params[:index_file_path])
          json_doc_file_path = remove_relative_path(params[:json_doc_file_path])
          # we omit base_dir validation in case of loading the data from other environments
          validate_string(index_file_path, "index_file_path")
          validate_string(json_doc_file_path, "json_doc_file_path")

          absolute_index_path = validate_file_existence(base_dir_path, index_file_path, "index_file_path")
          abosolute_json_path = validate_file_existence(base_dir_path, json_doc_file_path, "json_doc_file_path")

          [base_dir_path, absolute_index_path, abosolute_json_path]
        end

        def remove_relative_path(path)
          path.start_with?('./') ? path[2..] : path
        end

        def validate_file_existence(base_dir, file_path, name)
          file =
            base_dir.to_s.empty? ? file_path : File.join(base_dir, file_path)
          complete_path = File.absolute_path(file)

          raise raise_argument_error("#{name} does not exist at #{complete_path}") unless File.exist?(complete_path)

          complete_path
        end

        def load_as_hnsw_vectors(vectors)
          hnsw_vectors = []
          vectors.each do |vector|
            hnsw_vector = Document.new(
              content: vector[:document],
              embedding: vector[:embedding],
              metadata: vector[:metadata]
            )
            if vector[:metadata][:doc_id]
              hnsw_vectors[vector[:metadata][:doc_id]] = hnsw_vector
            else
              hnsw_vectors << hnsw_vector
            end
          end
          hnsw_vectors
        end
      end
    end
  end
end
