# frozen_string_literal: true

module Boxcars
  module VectorStores
    module InMemory
      MemoryVector = Struct.new(:content, :embedding, :metadatax)

      class AddDocuments
        include VectorStore

        def initialize(embedding_tool: :openai, documents: nil)
          validate_params(embedding_tool, documents)
          @embedding_tool = embedding_tool
          @documents = documents
          @memory_vectors = []
        end

        def call
          texts = @documents.map { |doc| doc[:page_content] }
          vectors = generate_vectors(texts)
          add_vectors(vectors, @documents)
          @memory_vectors
        end

        private

        def validate_params(embedding_tool, documents)
          raise ::Boxcars::ArgumentError, 'documents is nil' unless documents
          return if %i[openai tensorflow].include?(embedding_tool)

          raise ::Boxcars::ArgumentError, 'embedding_tool is invalid'
        end

        # returns array of documents with vectors
        def add_vectors(vectors, documents)
          vectors.zip(documents).each do |vector, doc|
            memory_vector = MemoryVector.new(doc[:page_content], vector, doc[:metadata])
            @memory_vectors << memory_vector
          end
        end

        def generate_vectors(texts)
          embeddings_method[:klass].call(
            texts: texts, client: embeddings_method[:client]
          )
        end

        def embeddings_method
          @embeddings_method ||=
            case @embedding_tool
            when :openai
              { klass: Boxcars::VectorStores::EmbedViaOpenAI, client: openai_client }
            when :tensorflow
              { klass: Boxcars::VectorStores::EmbedViaTensorflow, client: nil }
            end
        end

        def openai_client
          @openai_client ||= OpenAI::Client.new(access_token: ENV.fetch('OPENAI_API_KEY', nil))
        end
      end
    end
  end
end
