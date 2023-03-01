# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A Boxcar that interprets a prompt and executes SQL code to get answers
  class SQL < EngineBoxcar
    # the description of this engine boxcar
    SQLDESC = "useful for when you need to query a database for %<name>s."
    attr_accessor :connection

    # @param connection [ActiveRecord::Connection] The SQL connection to use for this boxcar.
    # @param engine [Boxcars::Engine] The engine to user for this boxcar. Can be inherited from a train if nil.
    # @param kwargs [Hash] Any other keyword arguments to pass to the parent class. This can include
    #   :name, :description, :prompt and :top_k
    def initialize(connection: nil, engine: nil, **kwargs)
      @connection = connection || ::ActiveRecord::Base.connection
      the_prompt = kwargs[prompt] || my_prompt
      kwargs[:stop] ||= ["Answer:"]
      name = kwargs[:name] || "database"
      super(name: name,
            description: kwargs[:description] || format(SQLDESC, name: name),
            engine: engine,
            prompt: the_prompt)
    end

    # @return Hash The additional variables for this boxcar.
    def prediction_additional
      { schema: schema, dialect: dialect }.merge super
    end

    private

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

    def get_embedded_sql_answer(text)
      code = text[/^SQLQuery: (.*)/, 1]
      Boxcars.debug code, :yellow
      output = connection.exec_query(code).to_a
      "Answer: #{output}"
    end

    def get_answer(text)
      case text
      when /^SQLQuery:/
        get_embedded_sql_answer(text)
      when /^Answer:/
        text
      else
        raise Boxcars::Error "Unknown format from engine: #{text}"
      end
    end

    TEMPLATE = <<~IPT
      Given an input question, first create a syntactically correct %<dialect>s query to run,
      then look at the results of the query and return the answer. Unless the user specifies
      in his question a specific number of examples he wishes to obtain, always limit your query
      to at most %<top_k>s results using a LIMIT clause. You can order the results by a relevant column
      to return the most interesting examples in the database.

      Never query for all the columns from a specific table, only ask for a the few relevant columns given the question.

      Pay attention to use only the column names that you can see in the schema description. Be careful to not query for columns that do not exist.
      Also, pay attention to which column is in which table.

      Use the following format:
      Question: "Question here"
      SQLQuery: "SQL Query to run"
      SQLResult: "Result of the SQLQuery"
      Answer: "Final answer here"

      Only use the following tables:
      %<schema>s

      Question: %<question>s
    IPT

    # The prompt to use for the engine.
    def my_prompt
      @my_prompt ||= Prompt.new(
        input_variables: [:question],
        other_inputs: [:top_k, :dialect, :table_info],
        output_variables: [:answer],
        template: TEMPLATE)
    end
  end
end
