# frozen_string_literal: true

module Boxcars
  module VectorStore
    module InMemory
      class BuildFromArray
        include VectorStore

        # @param embedding_tool [Symbol] :openai or other embedding tools
        # @param input_array [Array] array of hashes with :content and :metadata keys
        # each hash item should have content and metadata
        # [
        #   { content: "hello", metadata: { a: 1 } },
        #   { content: "hi", metadata: { a: 1 } },
        #   { content: "bye", metadata: { a: 1 } },
        #   { content: "what's this", metadata: { a: 1 } }
        # ]
        # @return [Hash] vector_store: array of hashes with :content, :metadata, and :embedding keys
        def initialize(embedding_tool: :openai, input_array: nil)
          validate_params(embedding_tool, input_array)
          @embedding_tool = embedding_tool
          @input_array = input_array
          @memory_vectors = []
        end

        # @return [Hash] vector_store: array of Inventor::VectorStore::Document
        def call
          texts = input_array.map { |doc| doc[:content] }
          vectors = generate_vectors(texts)
          add_vectors(vectors, input_array)

          {
            type: :in_memory,
            vector_store: memory_vectors
          }
        end

        private

        attr_reader :input_array, :memory_vectors

        def validate_params(embedding_tool, input_array)
          raise_argument_error('input_array is nil') unless input_array
          raise_argument_error('input_array must be an array') unless input_array.is_a?(Array)
          unless proper_document_array?(input_array)
            raise_argument_error('items in input_array needs to have content and metadata')
          end

          return if %i[openai tensorflow].include?(embedding_tool)

          raise_argument_error('embedding_tool is invalid')
        end

        def proper_document_array?(input_array)
          return false unless
            input_array.all? { |hash| hash.key?(:content) && hash.key?(:metadata) }

          true
        end

        # returns array of documents with vectors
        def add_vectors(vectors, input_array)
          vectors.zip(input_array).each do |vector, doc|
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
