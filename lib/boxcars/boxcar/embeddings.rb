# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  module Embeddings
    module ClassMethods
      EmbeddingsError = Class.new(StandardError)

      def call(*args, **kw_args)
        new(*args, **kw_args).call
      end
    end

    def self.included(base)
      base.extend(ClassMethods)

      class << base
        private :new
      end
    end
  end
end

require_relative "embeddings/document"
require_relative "embeddings/embed_via_open_ai"
require_relative "embeddings/split_text"
require_relative "embeddings/similarity_search"
require_relative "embeddings/hnswlib/hnswlib_config"
require_relative "embeddings/hnswlib/save_to_hnswlib"
require_relative "embeddings/hnswlib/build_vector_store"
require_relative "embeddings/hnswlib/similarity_search"
