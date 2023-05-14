# frozen_string_literal: true

require 'pg'

module PgvectorHelper
  # rubocop:disable Style/FetchEnvVar
  def conn
    @conn ||= if ENV['GITHUB_ACTIONS']
                PG.connect(dbname: "boxcars_test")
              else
                PG::Connection.new(ENV['DATABASE_URL'])
              end
  end
  # rubocop:enable Style/FetchEnvVar

  def create_items_table
    unless conn.exec("SELECT 1 FROM pg_extension WHERE extname = 'vector'").any?
      conn.exec("CREATE EXTENSION IF NOT EXISTS vector")
    end

    conn.exec("DROP TABLE IF EXISTS items")
    create_table_query = <<-SQL
      CREATE TABLE IF NOT EXISTS items (
        id bigserial PRIMARY KEY,
        content text,
        embedding vector(3),
        metadata jsonb
      );
    SQL

    conn.exec(create_table_query)
  end

  def add_vectors_to_database(documents:, table_name:, embedding_column_name:, content_column_name:, metadata_column_name:)
    documents.each do |document|
      embedding = document.embedding.map(&:to_f)
      content = document.content
      metadata = document.metadata.to_json

      if document.metadata[:id]
        id = document.metadata[:id]
        sql = <<-SQL
          INSERT INTO #{table_name} (id, #{embedding_column_name}, #{content_column_name}, #{metadata_column_name})
          VALUES ($1, $2, $3, $4)
          ON CONFLICT (id) DO UPDATE
          SET #{embedding_column_name} = EXCLUDED.#{embedding_column_name},
          #{content_column_name} = EXCLUDED.#{content_column_name},
          metadata = EXCLUDED.metadata
        SQL
        conn.exec_params(sql, [id, embedding, content, metadata])
      else
        sql = <<-SQL
          INSERT INTO #{table_name} (#{embedding_column_name}, #{content_column_name}, #{metadata_column_name})
          VALUES ($1, $2, $3)
        SQL
        conn.exec_params(sql, [embedding, content, metadata])
      end
    end
  end
end

RSpec.configure do |config|
  config.include PgvectorHelper
end
