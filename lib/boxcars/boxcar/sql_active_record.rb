# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A Boxcar that interprets a prompt and executes SQL code using Active Record to get answers
  class SQLActiveRecord < SQLBase
    # @param connection [ActiveRecord::Connection] The SQL connection to use for this boxcar.
    # @param tables [Array<String>] The tables to use for this boxcar. Will use all if nil.
    # @param except_tables [Array<String>] The tables to exclude from this boxcar. Will exclude none if nil.
    # @param kwargs [Hash] Any other keyword arguments to pass to the parent class. This can include
    #   :name, :description, :prompt, :top_k, :stop, and :engine
    def initialize(connection: nil, tables: nil, except_tables: nil, **kwargs)
      Boxcars::OptionalDependency.require!(
        "activerecord",
        feature: "Boxcars::SQLActiveRecord",
        require_as: "active_record"
      )
      connection ||= ::ActiveRecord::Base.connection
      super
    end

    private

    def table_schema(table)
      ["CREATE TABLE #{table} (",
       connection&.columns(table)&.map { |c| " #{c.name} #{c.sql_type} #{c.null ? "NULL" : "NOT NULL"}" }&.join(",\n"),
       ");"].join("\n")
    end

    def dialect
      connection.class.name.split("::").last.sub("Adapter", "")
    end

    def get_output(code)
      connection&.exec_query(code)
    end
  end
end
