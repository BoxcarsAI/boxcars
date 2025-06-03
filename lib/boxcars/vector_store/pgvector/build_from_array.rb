# frozen_string_literal: true

if Gem.loaded_specs.key?('pgvector') && Gem.loaded_specs.key?('pg')
  module Boxcars
    module VectorStore
      # install pgvector: https://github.com/pgvector/pgvector#installation-notes
      module Pgvector
        class BuildFromArray
          include VectorStore

          # initialize the vector store with the following parameters:
          #
          # @param params [Hash] A Hash containing the initial configuration.
          #
          # @option params [Symbol] :embedding_tool The embedding tool to use. Must be provided.
          # @option params [Array] :input_array The array of inputs to use for the embedding tool. Must be provided.
          # each hash item should have content and metadata
          # [
          #   { content: "hello", metadata: { a: 1 } },
          #   { content: "hi", metadata: { a: 1 } },
          #   { content: "bye", metadata: { a: 1 } },
          #   { content: "what's this", metadata: { a: 1 } }
          # ]
          # @option params [String] :database_url The URL of the database where embeddings are stored. Must be provided.
          # @option params [String] :table_name The name of the database table where embeddings are stored. Must be provided.
          # @option params [String] :embedding_column_name The name of the database column where embeddings are stored. required.
          # @option params [String] :content_column_name The name of the db column where content is stored. Must be provided.
          # @option params [String] :metadata_column_name The name of the database column where metadata is stored. required.
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

          # @return [Hash] vector_store: array of hashes with :content, :metadata, and :embedding keys
          def call
            texts = input_array.map { |doc| doc[:content] }
            vectors = generate_vectors(texts)
            add_vectors(vectors, input_array)
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
            raise_argument_error('input_array must be an array') unless input_array.is_a?(Array)
            unless proper_input_array?(input_array)
              raise_argument_error('items in input_array needs to have content and metadata')
            end
            return if %i[openai tensorflow].include?(embedding_tool)

            raise_argument_error('embedding_tool is invalid') unless %i[openai tensorflow].include?(embedding_tool)
          end

          def proper_input_array?(input_array)
            return false unless
              input_array.all? { |hash| hash.key?(:content) && hash.key?(:metadata) }

            true
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
else
  # Define placeholder modules/classes that raise an error if pgvector is not available
  module Boxcars
    module VectorStore
      module Pgvector
        class PgvectorNotAvailableError < StandardError
          DEFAULT_MESSAGE = "The 'pgvector' and 'pg' gems are required. Please add them to your Gemfile."
          def initialize(message = DEFAULT_MESSAGE)
            super
          end
        end

        class BuildFromArray
          def initialize(*_args)
            raise PgvectorNotAvailableError
          end

          def call(*_args)
            raise PgvectorNotAvailableError
          end
        end
      end
    end
  end
end
