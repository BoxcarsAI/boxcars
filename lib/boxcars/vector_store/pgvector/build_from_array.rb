# frozen_string_literal: true

module Boxcars
  module VectorStore
    # install pgvector: https://github.com/pgvector/pgvector#installation-notes
    module Pgvector
      class BuildFromArray
        include VectorStore

        # params =  {
        #   embedding_tool: embedding_tool,
        #   input_array: input_array,
        #   database_url: db_url,
        #   table_name: table_name,
        #   embedding_column_name: embedding_column_name,
        #   content_column_name: content_column_name,
        #   metadata_column_name: metadata_column_name
        # }
        def initialize(params)
          @embedding_tool = params[:embedding_tool] || :openai

          validate_params(embedding_tool, params[:input_array])

          @database_url = params[:database_url]
          @table_name = params[:table_name]
          @embedding_column_name = params[:embedding_column_name]
          @content_column_name = params[:content_column_name]
          @metadata_column_name = params[:metadata_column_name]

          @input_array = params[:input_array]
          @pg_vectors = []
        end

        def call
          texts = input_array
          vectors = generate_vectors(texts)
          add_vectors(vectors, texts)
          documents = save_vector_store

          {
            type: :pgvector,
            vector_store: documents
          }
        end

        private

        attr_reader :input_array, :embedding_tool, :pg_vectors, :database_url,
                    :table_name, :embedding_column_name, :content_column_name,
                    :metadata_column_name

        def validate_params(embedding_tool, input_array)
          raise_argument_error('input_array is nil') unless input_array
          return if %i[openai tensorflow].include?(embedding_tool)

          raise_argument_error('embedding_tool is invalid') unless %i[openai tensorflow].include?(embedding_tool)

          input_array.each do |item|
            next if item.key?(:content) && item.key?(:metadata)

            return raise_argument_error('embedding_tool is invalid')
          end
        end

        def add_vectors(vectors, texts)
          raise_argument_error("vectors are nil") unless vectors
          raise_argument_error("vectors and texts are not the same size") unless vectors.size == texts.size

          vectors.zip(texts) do |vector, doc|
            pg_vector = Document.new(
              content: doc[:content],
              embedding: vector[:embedding],
              metadata: doc[:metadata]
            )
            @pg_vectors << pg_vector
          end
        end

        def save_vector_store
          result = Boxcars::VectorStore::Pgvector::SaveToDatabase.call(
            pg_vectors: pg_vectors,
            database_url: database_url,
            table_name: table_name,
            embedding_column_name: embedding_column_name,
            content_column_name: content_column_name,
            metadata_column_name: metadata_column_name
          )
          raise_argument_error('Error saving vector store to database.') unless result

          result
        end
      end
    end
  end
end
