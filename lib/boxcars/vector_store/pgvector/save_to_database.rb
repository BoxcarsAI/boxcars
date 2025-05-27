# frozen_string_literal: true

if Gem.loaded_specs.key?('pgvector') && Gem.loaded_specs.key?('pg')
  require 'pg'
  require 'pgvector'

  module Boxcars
    module VectorStore
      module Pgvector
        class SaveToDatabase
          include VectorStore

          # @param pg_vectors [Array] array of Boxcars::VectorStore::Document
          # @param database_url [String] database url
          # @param table_name [String] table name
          # @param embedding_column_name [String] embedding column name
          # @param content_column_name [String] content column name
          # @param metadata_column_name [String] metadata column name
          # @return [Array] array of Boxcars::VectorStore::Document
          def initialize(params)
            validate_param_types(params)
            @db_connection = test_db_params(params)

            @table_name = params[:table_name]
            @content_column_name = params[:content_column_name]
            @embedding_column_name = params[:embedding_column_name]
            @metadata_column_name = params[:metadata_column_name]

            @pg_vectors = params[:pg_vectors]
          end

          # @return [Array] array of Boxcars::VectorStore::Document
          def call
            add_vectors_to_database
          end

          private

          attr_reader :database_url, :pg_vectors, :db_connection, :table_name,
                      :embedding_column_name, :content_column_name,
                      :metadata_column_name

          def validate_param_types(params)
            pg_vectors = params[:pg_vectors]

            raise_argument_error('pg_vectors must be an array') unless pg_vectors.is_a?(Array)
            raise_argument_error('missing data') if pg_vectors.empty?
            raise_argument_error('invalid vector_store') unless valid_vector_store?(pg_vectors)
            @database_url = params[:database_url]
            raise_argument_error('missing database_url argument') if @database_url.to_s.empty?
          end

          def valid_vector_store?(pg_vectors)
            pg_vectors.all? do |doc|
              doc.is_a?(Boxcars::VectorStore::Document)
            end
          rescue TypeError => e
            raise_argument_error(e.message)
          end

          def test_db_params(params)
            conn = ::PG::Connection.new(@database_url)

            check_db_connection(conn)
            check_vector_extension(conn)
            check_table_exists(conn, params[:table_name])
            check_column_exists(conn, params)

            registry = PG::BasicTypeRegistry.new.define_default_types
            ::Pgvector::PG.register_vector(registry)
            conn.type_map_for_queries = PG::BasicTypeMapForQueries.new(conn, registry: registry)
            conn.type_map_for_results = PG::BasicTypeMapForResults.new(conn, registry: registry)
            conn
          rescue PG::Error, NameError => e
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

          def check_column_exists(conn, params)
            column_names = %i[embedding_column_name content_column_name metadata_column_name]
            table_name = params[:table_name]

            column_names.each do |target|
              column_name = params[target]
              column_exists = conn.exec_params(
                "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = $1 AND column_name = $2)",
                [table_name, column_name]
              ).getvalue(0, 0) == "t"
              next if column_exists

              raise_argument_error("Column '#{column_name}' does not exist in table '#{table_name}'")
            end
          end

          def add_vectors_to_database
            pg_vectors.each do |document|
              embedding = document.embedding.map(&:to_f)
              content = document.content
              metadata = document.metadata.to_json

              if document.metadata[:id]
                id = document.metadata[:id]
                # directly inserting table_name, embedding_column_name, and content_column_name
                # into the SQL command. If these values are coming from an untrusted source,
                # there is a risk of SQL injection
                sql = <<-SQL
                  INSERT INTO #{table_name} (id, #{embedding_column_name}, #{content_column_name}, #{metadata_column_name})
                  VALUES ($1, $2, $3, $4)
                  ON CONFLICT (id) DO UPDATE
                  SET #{embedding_column_name} = EXCLUDED.#{embedding_column_name},
                      #{content_column_name} = EXCLUDED.#{content_column_name},
                      #{metadata_column_name} = EXCLUDED.#{metadata_column_name}
                SQL
                # parameters are given separately from the SQL command,
                # there's no risk of them being interpreted as part of the command.
                db_connection.exec_params(sql, [id, embedding, content, metadata])
              else
                sql = <<-SQL
                  INSERT INTO #{table_name} (#{embedding_column_name}, #{content_column_name}, #{metadata_column_name})
                  VALUES ($1, $2, $3)
                SQL
                db_connection.exec_params(sql, [embedding, content, metadata])
              end
            end
          rescue PG::Error => e
            raise_argument_error(e.message)
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

        class SaveToDatabase
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
