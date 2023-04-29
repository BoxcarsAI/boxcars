# frozen_string_literal: true

module Boxcars
  module VectorStores
    module InMemory
      class AddDocuments
        include VectorStore

        MemoryVector = Struct.new(:content, :embedding, :metadata)

        def initialize(embedding_tool:, documents: nil)
          validate_params(embedding_tool, documents)
          @embedding_tool = embedding_tool
          @documents = documents
          @memory_vectors = []
        end

        def call
          texts = @documents.map { |doc| doc[:page_content] }
          vectors = generate_vectors(texts)
          add_vectors(vectors, @documents)
        end

        private

        def validate_params(embedding_tool, documents)
          raise ::Boxcars::ArgumentError, 'documents is nil' unless documents

          valid_embedding_tools = [Boxcars::VectorStores::EmbedViaOpenAI, Boxcars::VectorStores::EmbedViaTensorflow]
          return if valid_embedding_tools.include?(embedding_tool.class) && documents.is_a?(Array)

          error_message = "embedding_tool must be an instance of a valid embedding class "\
                          "(e.g., EmbedViaOpenAI or EmbedViaTensorflow), "\
                          "and documents must be an array of hashes with :page_content key"

          raise ::Boxcars::ArgumentError, error_message
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
          @openai_client ||= OpenAI::Client.new(api_key: ENV.fetch('OPENAI_API_KEY'))
        end
      end
    end
  end
end
