# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A Boxcar that interprets a prompt and executes SQL code to get answers
  class SQL < EngineBoxcar
    # the description of this engine boxcar
    SQLDESC = "useful for when you need to query a database for %<name>s."
    LOCKED_OUT_TABLES = %w[schema_migrations ar_internal_metadata].freeze
    attr_accessor :connection

    # @param connection [ActiveRecord::Connection] The SQL connection to use for this boxcar.
    # @param tables [Array<String>] The tables to use for this boxcar. Will use all if nil.
    # @param except_tables [Array<String>] The tables to exclude from this boxcar. Will exclude none if nil.
    # @param kwargs [Hash] Any other keyword arguments to pass to the parent class. This can include
    #   :name, :description, :prompt, :top_k, :stop, and :engine
    def initialize(connection: nil, tables: nil, except_tables: nil, **kwargs)
      @connection = connection || ::ActiveRecord::Base.connection
      check_tables(tables, except_tables)
      kwargs[:name] ||= "Database"
      kwargs[:description] ||= format(SQLDESC, name: name)
      kwargs[:prompt] ||= my_prompt
      super(**kwargs)
    end

    # @return Hash The additional variables for this boxcar.
    def prediction_additional
      { schema: schema, dialect: dialect }.merge super
    end

    private

    def check_tables(rtables, exceptions)
      if rtables.is_a?(Array) && tables.length.positive?
        @requested_tables = rtables
        all_tables = tables
        rtables.each do |t|
          raise ArgumentError, "table #{t} needs to be an Active Record model" unless all_tables.include?(t)
        end
      elsif rtables
        raise ArgumentError, "tables needs to be an array of Strings"
      end
      @except_models = LOCKED_OUT_TABLES + exceptions.to_a
    end

    def tables
      connection&.tables
    end

    def table_schema(table)
      ["CREATE TABLE #{table} (",
       connection&.columns(table)&.map { |c| " #{c.name} #{c.sql_type} #{c.null ? "NULL" : "NOT NULL"}" }&.join(",\n"),
       ");"].join("\n")
    end

    def schema(except_tables: ['ar_internal_metadata'])
      wanted_tables = tables.to_a - except_tables
      wanted_tables.map(&method(:table_schema)).join("\n")
    end

    def dialect
      connection.class.name.split("::").last.sub("Adapter", "")
    end

    def clean_up_output(output)
      output = output.as_json if output.is_a?(::ActiveRecord::Result)
      output = 0 if output.is_a?(Array) && output.empty?
      output = output.first if output.is_a?(Array) && output.length == 1
      output = output[output.keys.first] if output.is_a?(Hash) && output.length == 1
      output = output.as_json if output.is_a?(::ActiveRecord::Relation)
      output
    end

    def get_embedded_sql_answer(text)
      code = text[/^SQLQuery: (.*)/, 1]
      Boxcars.debug code, :yellow
      output = clean_up_output(connection.exec_query(code))
      Result.new(status: :ok, answer: output, explanation: "Answer: #{output.to_json}", code: code)
    rescue StandardError => e
      Result.new(status: :error, answer: nil, explanation: "Error: #{e.message}", code: code)
    end

    def get_answer(text)
      case text
      when /^SQLQuery:/
        get_embedded_sql_answer(text)
      when /^Answer:/
        Result.from_text(text)
      else
        Result.from_error("Unknown format from engine: #{text}")
      end
    end

    CTEMPLATE = [
      [:system, "Given an input question, first create a syntactically correct %<dialect>s SQL query to run, " \
                "then look at the results of the query and return the answer. Unless the user specifies " \
                "in her question a specific number of examples he wishes to obtain, always limit your query " \
                "to at most %<top_k>s results using a LIMIT clause. You can order the results by a relevant column " \
                "to return the most interesting examples in the database.\n" \
                "Never query for all the columns from a specific table, only ask for the elevant columns given the question.\n" \
                "Pay attention to use only the column names that you can see in the schema description. Be careful to " \
                "not query for columns that do not exist. Also, pay attention to which column is in which table."],
      [:system, "Use the following format:\n" \
                "Question: 'Question here'\n" \
                "SQLQuery: 'SQL Query to run'\n" \
                "SQLResult: 'Result of the SQLQuery'\n" \
                "Answer: 'Final answer here'"],
      [:system, "Only use the following tables:\n%<schema>s"],
      [:assistant, "Question: %<question>s"]
    ].freeze

    # The prompt to use for the engine.
    def my_prompt
      @conversation ||= Conversation.new(lines: CTEMPLATE)
      @my_prompt ||= ConversationPrompt.new(
        conversation: @conversation,
        input_variables: [:question],
        other_inputs: [:top_k, :dialect, :table_info],
        output_variables: [:answer])
    end
  end
end
