# frozen_string_literal: true

module Boxcars
  module VectorStore
    class EmbedViaTensorflow
      include VectorStore

      def call
        raise NotImplementedError
      end
    end
  end
end
