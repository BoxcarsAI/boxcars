# frozen_string_literal: true

module Boxcars
  module Embeddings
    class FakeEmbeddings
      def initialize(params = {})
        # Initialize any params if required
      end

      def embed_documents(documents)
        documents.map { [0.1, 0.2, 0.3, 0.4] }
      end

      def embed_query(_)
        [0.1, 0.2, 0.3, 0.4]
      end
    end
  end
end
