# frozen_string_literal: true

require 'hnswlib'
require 'json'
require 'fileutils'

module Boxcars
  module Embeddings
    module Hnswlib
      class SaveToHnswlib
        include Embeddings

        # @param document_embeddings [Array] An array of hashes containing the document id, document text, and embedding.
        # @param index_file_path [String] The path to the index file.
        # @param hnswlib_config [Boxcars::Embeddings::Hnswlib::Config] The config object for the hnswlib index.
        # @option json_doc_file_path [String] Optional. The path to the json file containing the document text.
        def initialize(document_embeddings:, index_file_path:, hnswlib_config:, json_doc_file_path: nil)
          @document_embeddings = document_embeddings
          @index_file_path = index_file_path
          @json_doc_file_path = json_doc_file_path

          @hnswlib_config = hnswlib_config
          @index = ::Hnswlib::HnswIndex.new(
            n_features: hnswlib_config.dim,
            max_item: hnswlib_config.max_item,
            metric: hnswlib_config.metric
          )
        end

        def call
          validate_params
          document_texts = {}

          document_embeddings.each do |embedding|
            doc_id = embedding[:doc_id]
            index.add_item(doc_id, embedding[:embedding])
            document_texts[doc_id] = embedding[:document]
          end

          if json_doc_file_path
            FileUtils.mkdir_p(File.dirname(json_doc_file_path))
            File.write(json_doc_file_path, document_texts.to_json)
          end

          FileUtils.mkdir_p(File.dirname(index_file_path))
          index.save(index_file_path)
        end

        private

        attr_reader :index, :document_embeddings, :index_file_path, :json_doc_file_path, :hnswlib_config

        def validate_params
          raise_error("document_embeddings must be an array") unless document_embeddings.is_a?(Array)
          raise_error("dim must be an integer") unless hnswlib_config.dim.is_a?(Integer)
          raise_error("index_file_path must be a string") unless index_file_path.is_a?(String)

          [index_file_path, json_doc_file_path].each do |path|
            check_parent_directory(path)
          end
        end

        def check_parent_directory(path)
          return unless path

          parent_dir = File.dirname(path)
          raise_error('parent directory must exist') unless File.directory?(parent_dir)
        end

        def raise_error(message)
          raise ::Boxcars::ValueError, message
        end
      end
    end
  end
end
