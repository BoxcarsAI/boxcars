# frozen_string_literal: true

module Boxcars
  module VectorStore
    module InMemory
      class BuildFromDocumentArray
        include VectorStore

        # @param embedding_tool [Symbol] :openai or other embedding tools
        # @param documents [Array] array of hashes with :content and :metadata keys
        # @return [Hash] vector_store: array of hashes with :content, :metadata, and :embedding keys
        def initialize(embedding_tool: :openai, documents: nil)
          validate_params(embedding_tool, documents)
          @embedding_tool = embedding_tool
          @documents = documents
          @memory_vectors = []
        end

        def call
          texts = documents
          vectors = generate_vectors(texts)
          add_vectors(vectors, documents)
          {
            type: :in_memory,
            vector_store: memory_vectors
          }
        end

        private

        attr_reader :documents, :memory_vectors

        def validate_params(embedding_tool, documents)
          raise_argument_error('documents is nil') unless documents
          return if %i[openai tensorflow].include?(embedding_tool)

          raise_argument_error('embedding_tool is invalid')
        end

        # returns array of documents with vectors
        def add_vectors(vectors, documents)
          vectors.zip(documents).each do |vector, doc|
            memory_vector = Document.new(
              content: doc[:content],
              embedding: vector[:embedding],
              metadata: doc[:metadata].merge(dim: vector[:dim])
            )
            @memory_vectors << memory_vector
          end
        end
      end
    end
  end
end
