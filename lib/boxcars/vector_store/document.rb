# frozen_string_literal: true

module Boxcars
  module VectorStore
    class Document
      attr_accessor :content, :metadata, :embedding

      def initialize(fields = {})
        @content = fields[:content] || ""
        @embedding = fields[:embedding] || []
        @metadata = fields[:metadata] || {}
      end
    end
  end
end
