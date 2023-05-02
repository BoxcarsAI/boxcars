# frozen_string_literal: true

module Boxcars
  module VectorStores
    class EmbedViaTensorflow
      include VectorStore
      def call
        raise NotImplementedError
      end
    end
  end
end
