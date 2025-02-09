# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A Boxcar that interprets a prompt and executes SQL code to get answers
  # Use one of the subclasses for ActiveRecord or Sequel
  # @abstract
  class SQLBaseV2 < EngineBoxcar
    # the description of this engine boxcar
    SQLDESC = "useful for when you need to query a database for %<name>s."
    LOCKED_OUT_TABLES = %w[schema_migrations ar_internal_metadata].freeze
    attr_accessor :connection, :the_tables

    # @param connection [ActiveRecord::Connection] or [Sequel Object] The SQL connection to use for this boxcar.
    # @param tables [Array<String>] The tables to use for this boxcar. Will use all if nil.
    # @param except_tables [Array<String>] The tables to exclude from this boxcar. Will exclude none if nil.
    # @param kwargs [Hash] Any other keyword arguments to pass to the parent class. This can include
    #   :name, :description, :prompt, :top_k, :stop, and :engine
    def initialize(connection: nil, tables: nil, except_tables: nil, **kwargs)
      @connection = connection
      check_tables(tables, except_tables)
      kwargs[:name] ||= "Database"
      kwargs[:description] ||= format(SQLDESC, name: name)
      kwargs[:prompt] ||= my_prompt
      kwargs[:stop] ||= ["SQLResult:"]

      super(**kwargs)
    end

    # @return Hash The additional variables for this boxcar.
    def prediction_additional(_inputs)
      { schema: schema, dialect: dialect }.merge super
    end

    private

    def check_tables(rtables, exceptions)
      requested_tables = nil
      if rtables.is_a?(Array) && tables.length.positive?
        requested_tables = rtables
        all_tables = tables
        rtables.each do |t|
          raise ArgumentError, "table #{t} not found in database" unless all_tables.include?(t)
        end
      elsif rtables
        raise ArgumentError, "tables needs to be an array of Strings"
      else
        requested_tables = tables.to_a
      end
      except_tables = LOCKED_OUT_TABLES + exceptions.to_a
      @the_tables = requested_tables - except_tables
    end

    def tables
      connection&.tables
    end

    # abstract method to get the prompt for this boxcar
    def table_schema(table)
      raise NotImplementedError
    end

    def schema
      the_tables.map(&method(:table_schema)).join("\n")
    end

    # abstract method to get the prompt for this boxcar
    def dialect
      raise NotImplementedError
    end

    # abstract method to get the output for the last query
    def get_output(code)
      raise NotImplementedError
    end

    def clean_up_output(code)
      output = get_output(code)
      output = output.as_json if output.is_a?(::ActiveRecord::Result)
      output = 0 if output.is_a?(Array) && output.empty?
      output = output.first if output.is_a?(Array) && output.length == 1
      output = output[output.keys.first] if output.is_a?(Hash) && output.length == 1
      output = output.as_json if output.is_a?(::ActiveRecord::Relation)
      output
    end

    def get_embedded_sql_answer(text)
      code = text[/^SQLQuery: (.*)/, 1]
      code = extract_code text.split('SQLQuery:').last.strip
      Boxcars.debug code, :yellow
      output = clean_up_output(code)
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
        Result.from_error("Your answer wasn't formatted properly - try again. I expected your answer to " \
                          "start with \"SQLQuery:\".")
      end
    end

    # The prompt to use for the engine.
    def my_prompt
      conv_template = [
        Boxcar.syst("Given an input question, create a syntactically correct SQL query, ",
                    "return the query as the answer.",
                    "You can order the results by a relevant column to return the most interesting examples in the database.\n",
                    "Do not query for all the columns from a specific table, only relevant columns given the question.\n",
                    "When building the sql query, use only the following schema description: #{schema}\n",
                    "When your task is complete, use the following format:\n",
                    "Question: 'Question here'\n",
                    "SQLQuery: 'SQL Query to run'\n",
                    "Answer: 'Final answer here'"),
        Boxcar.user("Question: %<question>s")
      ]
      @conversation ||= Conversation.new(lines: conv_template)
      @my_prompt ||= ConversationPrompt.new(
        conversation: @conversation,
        input_variables: [:question],
        other_inputs: [:top_k, :dialect, :table_info],
        output_variables: [:answer])
    end
  end
end
