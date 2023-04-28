# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  module VectorStore
    module ClassMethods
      VectorStoresError = Class.new(StandardError)

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

require_relative "vector_stores/document"
require_relative "vector_stores/embed_via_open_ai"
require_relative "vector_stores/split_text"
require_relative "vector_stores/similarity_search"
require_relative "vector_stores/hnswlib/hnswlib_config"
require_relative "vector_stores/hnswlib/save_to_hnswlib"
require_relative "vector_stores/hnswlib/build_vector_store"
require_relative "vector_stores/hnswlib/hnswlib_search"
