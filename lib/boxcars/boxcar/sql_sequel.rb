# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A Boxcar that interprets a prompt and executes Sequel SQL code to get answers
  class SQLSequel < SQLBase
    # @param connection [SEQUEL Database object] The Sequel connection to use for this boxcar.
    # @param tables [Array<String>] The tables to use for this boxcar. Will use all if nil.
    # @param except_tables [Array<String>] The tables to exclude from this boxcar. Will exclude none if nil.
    # @param kwargs [Hash] Any other keyword arguments to pass to the parent class. This can include
    #   :name, :description, :prompt, :top_k, :stop, and :engine
    def initialize(connection: nil, tables: nil, except_tables: nil, **kwargs)
      Boxcars::OptionalDependency.require!("sequel", feature: "Boxcars::SQLSequel")
      super
    end

    private

    def table_schema(table)
      ["CREATE TABLE #{table} (",
       connection&.schema(table)&.map { |c| " #{c[0]} #{c[1][:type]} #{c[1][:allow_null] ? "NULL" : "NOT NULL"}" }&.join(",\n"),
       ");"].join("\n")
    end

    def dialect
      connection.database_type
    end

    def get_output(code)
      connection[code].all
    end
  end
end
