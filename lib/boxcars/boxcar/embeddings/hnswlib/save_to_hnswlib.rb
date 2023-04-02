# frozen_string_literal: true

require 'hnswlib'
require 'json'

module Boxcars
  module Embeddings
    module Hnswlib
      class SaveToHnswlib
        include Embeddings

        attr_reader :index, :document_embeddings, :index_file_path, :doc_text_file_path, :hnswlib_config

        def initialize(document_embeddings:, index_file_path:, doc_text_file_path:, hnswlib_config:)
          @document_embeddings = document_embeddings
          @index_file_path = index_file_path
          @doc_text_file_path = doc_text_file_path

          @hnswlib_config = hnswlib_config
          @index = ::Hnswlib::HnswIndex.new(
            n_features: hnswlib_config.dim,
            max_item: hnswlib_config.max_item,
            metric: hnswlib_config.metric
          )
        end

        def call
          document_texts = {}

          document_embeddings.each do |embedding|
            doc_id = embedding[:doc_id]
            index.add_item(doc_id, embedding[:embedding])
            document_texts[doc_id] = embedding[:document]
          end

          FileUtils.mkdir_p(File.dirname(index_file_path))
          FileUtils.mkdir_p(File.dirname(doc_text_file_path))

          index.save(index_file_path)
          File.write(doc_text_file_path, document_texts.to_json)
        end

        private

        def validate_params(document_embeddings, dim, index_file_path)
          raise_error("document_embeddings must be an array") unless document_embeddings.is_a?(Array)
          raise_error("dim must be an integer") unless dim.is_a?(Integer)
          raise_error("index_file_path must be a string") unless index_file_path.is_a?(String)
        end

        def raise_error(message)
          raise ::Boxcars::ValueError, message
        end
      end
    end
  end
end
