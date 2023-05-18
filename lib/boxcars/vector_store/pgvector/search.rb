# frozen_string_literal: true

require 'pg'
require 'json'

module Boxcars
  module VectorStore
    module Pgvector
      class Search
        include VectorStore

        # required params:
        # {
        #   type: :pgvector,
        #   vector_store: {
        #     database_url: database_url,
        #     table_name: table_name,
        #     embedding_column_name: embedding_column_name,
        #     content_column_name: content_column_name,
        #     metadata_column_name: metadata_column_name
        #   }
        # }
        def initialize(params)
          vector_store = validate_params(params)
          db_url = validate_vector_store(vector_store)
          @db_connection = test_db(db_url)

          @vector_documents = params[:vector_documents]
        end

        def call(query_vector:, count: 1)
          raise ::Boxcars::ArgumentError, 'query_vector is empty' if query_vector.empty?

          search(query_vector, count)
        end

        private

        attr_reader :vector_documents, :vector_store, :db_connection,
                    :table_name, :embedding_column_name, :content_column_name

        def validate_params(params)
          @vector_documents = params[:vector_documents]

          raise_argument_error('vector_documents is nil') unless vector_documents
          raise_arugment_error('vector_documents must be a hash') unless vector_documents.is_a?(Hash)
          raise_arugment_error('type must be pgvector') unless vector_documents[:type] == :pgvector

          @vector_store = vector_documents[:vector_store]
          @vector_store
        end

        def validate_vector_store(vector_store)
          raise_arugment_error('vector_store is nil') unless vector_store
          raise_arugment_error('vector_store must be a hash') unless vector_store.is_a?(Hash)
          raise_arugment_error('vector_store must have a table_name') unless vector_store[:table_name]
          raise_arugment_error('vector_store must have a embedding_column_name') unless vector_store[:embedding_column_name]
          raise_arugment_error('vector_store must have a content_column_name') unless vector_store[:content_column_name]
          raise_argument_error('missing DATABASE_URL') unless vector_store[:database_url]

          vector_store[:database_url]
        end

        def test_db(db_url)
          conn = ::PG::Connection.new(db_url)

          check_db_connection(conn)
          check_vector_extension(conn)
          check_table_exists(conn, vector_store[:table_name])
          check_column_exists(conn)

          @table_name = vector_store[:table_name]
          @embedding_column_name = vector_store[:embedding_column_name]
          @content_column_name = vector_store[:content_column_name]

          conn
        rescue PG::Error, PG::UndefinedTable, NameError => e
          raise_argument_error(e.message)
        end

        def check_db_connection(conn)
          return if conn.status == PG::CONNECTION_OK

          raise_argument_error("PostgreSQL connection is not ok")
        end

        def check_vector_extension(conn)
          return if conn.exec("SELECT 1 FROM pg_extension WHERE extname = 'vector'").any?

          raise_argument_error("PostgreSQL 'vector' extension is not installed")
        end

        def check_table_exists(conn, table_name)
          table_exists = conn.exec_params(
            "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = $1)", [table_name]
          ).getvalue(0, 0) == "t"
          return if table_exists

          raise_argument_error("Table '#{table_name}' does not exist")
        end

        def check_column_exists(conn)
          column_names = %i[embedding_column_name content_column_name]
          table_name = vector_store[:table_name]

          column_names.each do |target|
            column_name = vector_store[target]
            column_exists = conn.exec_params(
              "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = $1 AND column_name = $2)",
              [table_name, column_name]
            ).getvalue(0, 0) == "t"
            next if column_exists

            raise_argument_error("Column '#{column_name}' does not exist in table '#{table_name}'")
          end
        end

        def search(query_vector, num_neighbors)
          sql = <<-SQL
            SELECT *, #{embedding_column_name} <-> $1 AS distance FROM #{table_name}
            ORDER BY #{embedding_column_name} <-> $1
            LIMIT #{num_neighbors}
          SQL
          result = db_connection.exec_params(sql, [query_vector.to_s]).to_a
          return [] if result.empty?

          result.map { |hash| hash.transform_keys(&:to_sym) }
                .map do |item|
                  {
                    document: Boxcars::VectorStore::Document.new(
                      content: item[:content],
                      embedding: JSON.parse(item[:embedding]),
                      metadata: JSON.parse(item[:metadata], symbolize_names: true)
                    ),
                    distance: item[:distance].to_f
                  }
                end
        rescue StandardError => e
          raise_argument_error("Error searching for #{query_vector}: #{e.message}")
        end
      end
    end
  end
end
