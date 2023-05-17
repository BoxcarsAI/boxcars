# frozen_string_literal: true

require 'hnswlib'
require 'json'
require 'fileutils'

module Boxcars
  module VectorStore
    module Hnswlib
      class SaveToHnswlib
        include VectorStore

        # @param document_embeddings [Array] An array of hashes containing the document id, document text, and embedding.
        # @param index_file_path [String] The path to the index file.
        # @option json_doc_file_path [String] Optional. The path to the json file containing the document text.
        def initialize(hnsw_vectors_array)
          @metadata = hnsw_vectors_array&.first&.metadata
          validate_params(hnsw_vectors_array, metadata)

          @vectors = hnsw_vectors_array
          @index_file_path = metadata[:index_file_path]
          @json_doc_file_path = metadata[:json_doc_file_path] || @index_file_path.gsub(/\.bin$/, '.json')

          @metric = metadata[:metric] || "l2"
          @dim = metadata[:dim]
          @max_item = metadata[:max_item] || 10000

          @index = ::Hnswlib::HierarchicalNSW.new(
            space: @metric,
            dim: @dim
          )
          @index.init_index(max_elements: @max_item)
        end

        def call
          document_texts = add_vectors_to_index
          write_files(index, document_texts)
        end

        private

        attr_reader :metadata, :index, :vectors, :index_file_path, :json_doc_file_path, :metric, :dim, :max_item

        def validate_params(hnsw_vectors_array, metadata)
          raise_argument_error('argument must be an array') unless hnsw_vectors_array.is_a?(Array)
          raise_argument_error('missing data') if hnsw_vectors_array.empty?
          raise_error('missing metadata') unless metadata || metadata.empty?

          raise_argument_error("dim must be an integer") unless metadata[:dim].is_a?(Integer)
          raise_argument_error('missing dim') unless metadata[:dim]
          raise_argument_error('missing index_file_path') unless metadata[:index_file_path]

          check_parent_directory(metadata[:index_file_path])
          check_parent_directory(metadata[:json_doc_file_path])
        end

        def add_vectors_to_index
          document_texts = []

          vectors.each do |item|
            index.add_point(item.embedding, item.metadata[:doc_id])

            document_texts << {
              doc_id: item.metadata[:doc_id],
              embedding: item.embedding,
              document: item.content,
              metadata: item.metadata
            }
          end
          document_texts
        end

        def write_files(index, document_texts)
          FileUtils.mkdir_p(File.dirname(json_doc_file_path))
          File.write(json_doc_file_path, document_texts.to_json)

          FileUtils.mkdir_p(File.dirname(index_file_path))
          index.save_index(index_file_path)
        end

        def check_parent_directory(path)
          return unless path

          parent_dir = File.dirname(path)
          raise_argument_error('parent directory must exist') unless File.directory?(parent_dir)
        end
      end
    end
  end
end
