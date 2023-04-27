# frozen_string_literal: true

module Boxcars
  module VectorStores
    class Document
      attr_accessor :page_content, :metadata

      def initialize(fields = {})
        @page_content = fields[:page_content] || ""
        @metadata = fields[:metadata] || {}
      end
    end
  end
end
