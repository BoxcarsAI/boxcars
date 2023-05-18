# frozen_string_literal: true

require 'pgvector'
require 'fileutils'
require 'json'

module Boxcars
  module VectorStore
    module Pgvector
      class BuildFromFiles
        include VectorStore

        # params = {
        #   training_data_path: training_data_path,
        #   split_chunk_size: 200,
        #   embedding_tool: embedding_tool,
        #   database_url: db_url,
        #   table_name: table_name,
        #   embedding_column_name: embedding_column_name,
        #   content_column_name: content_column_name
        # }
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

          raise_argument_error('training_data_path parent directory must exist') unless File.directory?(training_data_dir)
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
