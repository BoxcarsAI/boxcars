# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A Boxcar that interprets a prompt and executes SQL code to get answers
  class SQL < LLMBoxcar
    SQLDESC = "useful for when you need to query a SQL database"
    attr_accessor :connection, :input_key

    # @param connection [ActiveRecord::Connection] The SQL connection to use for this boxcar.
    # @param prompt [Boxcars::LLMPrompt] The prompt to use for this boxcar.
    # @param name [String] The name of the boxcar. Defaults to classname.
    # @param description [String] A description of the boxcar.
    # @param llm [Boxcars::LLM] The LLM to user for this boxcar. Can be inherited from a conductor if nil.
    # @param input_key [Symbol] The key to use for the input. Defaults to :question.
    # @param output_key [Symbol] The key to use for the output. Defaults to :answer.
    def initialize(connection:, llm: nil, input_key: :question, output_key: :answer, **kwargs)
      @connection = connection
      @input_key = input_key
      the_prompt = kwargs[prompt] || my_prompt
      super(name: kwargs[:name] || "SQLdatabase",
            description: kwargs[:description] || SQLDESC,
            llm: llm,
            prompt: the_prompt,
            output_key: output_key)
    end

    def input_keys
      [input_key]
    end

    def output_keys
      [output_key]
    end

    def call(inputs:)
      t = predict(question: inputs[input_key], dialect: dialect, top_k: 5, table_info: schema, stop: ["SQLQuery:"]).strip
      answer = get_answer(t)
      puts answer.colorize(:magenta)
      { output_key => answer }
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
      # connection.instance_variable_get "@config"[:adapter]
      connection.class.name.split("::").last.sub("Adapter", "")
    end

    def get_embedded_sql_answer(text)
      code = text[/^SQLQuery: (.*)/, 1]
      puts code.colorize(:yellow)
      output = connection.exec_query(code).to_a
      puts "Answer: #{output}"
      "Answer: #{output}"
    end

    def get_answer(text)
      case text
      when /^SQLQuery:/
        get_embedded_sql_answer(text)
      when /^Answer:/
        text
      else
        raise Boxcars::Error "Unknown format from LLM: #{text}"
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
      %<table_info>s

      Question: %<question>s
    IPT

    # The prompt to use for the LLM.
    def my_prompt
      @my_prompt ||= LLMPrompt.new(input_variables: [:question, :dialect, :top_k], template: TEMPLATE)
    end

    # DECIDER_TEMPLATE = <<~DPT
    #   Given the below input question and list of potential tables, output a comma separated list of the table names that may
    #   be necessary to answer this question.
    #   Question: %<query>s
    #   Table Names: %<table_names>s
    #   Relevant Table Names:
    # DPT
    # DECIDER_PROMPT = LLMPrompt.new(
    #   input_variables: %i[query table_names],
    #   template: DECIDER_TEMPLATE,
    #   output_parser: CommaSeparatedListOutputParser
    # )
  end
end
