# frozen_string_literal: true

if Gem.loaded_specs.key?('pgvector') && Gem.loaded_specs.key?('pg')
  require 'pgvector'
  require 'fileutils'
  require 'json'

  module Boxcars
    module VectorStore
      module Pgvector
        class BuildFromFiles
          include VectorStore

          # @param training_data_path [String] path to training data files
          # @param split_chunk_size [Integer] number of characters to split the text into
          # @param embedding_tool [Symbol] embedding tool to use
          # @param database_url [String] database url
          # @param table_name [String] table name
          # @param embedding_column_name [String] embedding column name
          # @param content_column_name [String] content column name
          # @param metadata_column_name [String] metadata column name
          # @return [Hash] vector_store: array of hashes with :content, :metadata, and :embedding keys
          def initialize(params)
            @split_chunk_size = params[:split_chunk_size] || 2000
            @training_data_path = File.absolute_path(params[:training_data_path])
            @embedding_tool = params[:embedding_tool] || :openai

            validate_params(embedding_tool, training_data_path)

            @database_url = params[:database_url]
            @table_name = params[:table_name]
            @embedding_column_name = params[:embedding_column_name]
            @content_column_name = params[:content_column_name]
            @metadata_column_name = params[:metadata_column_name]

            @pg_vectors = []
          end

          # @return [Hash] vector_store: array of Inventor::VectorStore::Document
          def call
            data = load_data_files(training_data_path)
            texts = split_text_into_chunks(data)
            embeddings = generate_vectors(texts)
            add_vectors(embeddings, texts)
            documents = save_vector_store

            {
              type: :pgvector,
              vector_store: documents
            }
          end

          private

          attr_reader :split_chunk_size, :training_data_path, :embedding_tool, :database_url,
                      :table_name, :embedding_column_name, :content_column_name,
                      :metadata_column_name, :pg_vectors

          def validate_params(embedding_tool, training_data_path)
            training_data_dir = File.dirname(training_data_path.gsub(/\*{1,2}/, ''))

            raise_argument_error('training_data_path parent directory must exist') unless Dir.exist?(training_data_dir)
            raise_argument_error('No files found at the training_data_path pattern') if Dir.glob(training_data_path).empty?
            return if %i[openai tensorflow].include?(embedding_tool)

            raise_argument_error('embedding_tool is invalid')
          end

          def add_vectors(vectors, texts)
            vectors.map.with_index do |vector, index|
              pg_vector = Document.new(
                content: texts[index],
                embedding: vector[:embedding],
                metadata: {
                  doc_id: index,
                  training_data_path: training_data_path
                }
              )
              pg_vectors << pg_vector
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

        class BuildFromFiles
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
