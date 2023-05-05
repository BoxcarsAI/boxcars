# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  module VectorStore
    module ClassMethods
      VectorStoreError = Class.new(StandardError)

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

require_relative "vector_store/document"
require_relative "vector_store/embed_via_open_ai"
require_relative "vector_store/embed_via_tensorflow"
require_relative "vector_store/split_text"
require_relative "vector_store/similarity_search"
require_relative "vector_store/hnswlib/hnswlib_config"
require_relative "vector_store/hnswlib/save_to_hnswlib"
require_relative "vector_store/hnswlib/build_vector_store"
require_relative "vector_store/hnswlib/hnswlib_search"
require_relative "vector_store/in_memory/add_documents"
require_relative "vector_store/in_memory/search"
