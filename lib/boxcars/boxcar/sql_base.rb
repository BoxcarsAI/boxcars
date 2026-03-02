# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A Boxcar that interprets a prompt and executes SQL code to get answers.
  # Use one of the subclasses for ActiveRecord or Sequel.
  # @abstract
  class SQLBase < EngineBoxcar
    # Default description for this boxcar.
    SQLDESC = "useful for when you need to query a database for %<name>s."
    LOCKED_OUT_TABLES = %w[schema_migrations ar_internal_metadata].freeze
    # SQL keywords that indicate a write operation.
    WRITE_SQL_KEYWORDS = %w[INSERT UPDATE DELETE DROP ALTER CREATE TRUNCATE REPLACE MERGE UPSERT
                            GRANT REVOKE LOCK CALL EXEC EXECUTE].freeze

    attr_accessor :connection, :the_tables, :context, :read_only, :approval_callback

    # @param connection [ActiveRecord::Connection] or [Sequel Object] The SQL connection to use for this boxcar.
    # @param tables [Array<String>] The tables to use for this boxcar. Will use all if nil.
    # @param except_tables [Array<String>] The tables to exclude from this boxcar. Will exclude none if nil.
    # @param read_only [Boolean] Whether to restrict to read-only SQL. Defaults to true unless approval_callback is given.
    # @param approval_callback [Proc] A function to call to approve write SQL. Receives the SQL string. Defaults to nil.
    # @param kwargs [Hash] Any other keyword arguments to pass to the parent class. This can include
    #   :name, :description, :prompt, :top_k, :stop, and :engine
    def initialize(connection: nil, tables: nil, except_tables: nil, context: nil, read_only: nil,
                   approval_callback: nil, **kwargs)
      @context = context
      @connection = connection
      @approval_callback = approval_callback
      @read_only = read_only.nil? ? !approval_callback : read_only
      check_tables(tables, except_tables)
      kwargs[:name] ||= "Database"
      kwargs[:description] ||= format(SQLDESC, name:)
      kwargs[:prompt] ||= my_prompt
      kwargs[:stop] ||= ["SQLResult:"]

      super(**kwargs)
    end

    # @return [Hash] The additional variables for this boxcar.
    def prediction_additional(_inputs)
      ctx = @context.to_s.strip
      context_str = ctx.empty? ? "" : "\n\nAdditional context:\n#{ctx}"
      { schema:, dialect:, context: context_str }.merge super
    end

    CTEMPLATE = [
      syst("Given an input question, first create a syntactically correct %<dialect>s SQL query to run, ",
           "then look at the results of the query and return the answer. Unless the user specifies ",
           "in her question a specific number of examples he wishes to obtain, always limit your query ",
           "to at most %<top_k>s results using a LIMIT clause. You can order the results by a relevant column ",
           "to return the most interesting examples in the database.\n",
           "Never query for all the columns from a specific table, only ask for the relevant columns given the question.\n",
           "Pay attention to use only the column names that you can see in the schema description. Be careful to ",
           "not query for columns that do not exist. Also, pay attention to which column is in which table.\n",
           "Use the following format:\n",
           "Question: 'Question here'\n",
           "SQLQuery: 'SQL Query to run'\n",
           "SQLResult: 'Result of the SQLQuery'\n",
           "Answer: 'Final answer here'"),
      syst("Only use the following tables:\n%<schema>s%<context>s"),
      user("Question: %<question>s")
    ].freeze

    # @return [Boolean] Whether this boxcar is in read-only mode.
    def read_only?
      read_only
    end

    private

    # Check if a SQL statement is safe (read-only) to run.
    # Strips string literals first to avoid false positives on values like 'DELETE ME'.
    # @param sql [String] The SQL statement to check.
    # @return [Boolean] true if the SQL appears to be a read-only statement.
    def sql_safe_to_run?(sql)
      without_strings = sql.gsub(/'([^'\\]*(\\.[^'\\]*)*)'/, "''")
      upper = without_strings.upcase
      WRITE_SQL_KEYWORDS.none? { |kw| upper.match?(/\b#{kw}\b/) }
    end

    # Check if the SQL is approved for execution.
    # @param sql [String] The SQL statement to check.
    # @return [Boolean] true if approved.
    def approved?(sql)
      return true if sql_safe_to_run?(sql)

      if read_only?
        Boxcars.error("Cannot execute write SQL in read-only mode: #{sql}", :red)
        return false
      end

      return approval_callback.call(sql) if approval_callback.is_a?(Proc)

      true
    end

    def check_tables(rtables, exceptions)
      requested_tables = nil
      if rtables.is_a?(Array)
        requested_tables = rtables
        all_tables = tables.to_a
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
      output = output.as_json if defined?(::ActiveRecord::Result) && output.is_a?(::ActiveRecord::Result)
      output = 0 if output.is_a?(Array) && output.empty?
      output = output.first if output.is_a?(Array) && output.length == 1
      output = output[output.keys.first] if output.is_a?(Hash) && output.length == 1
      output = output.as_json if defined?(::ActiveRecord::Relation) && output.is_a?(::ActiveRecord::Relation)
      output
    end

    def get_embedded_sql_answer(text)
      code = text[/^SQLQuery: (.*)/, 1]
      code = extract_code text.split('SQLQuery:').last.strip
      Boxcars.debug code, :yellow
      raise Boxcars::SecurityError, "Permission to execute write SQL denied" unless approved?(code)

      output = clean_up_output(code)
      Result.new(status: :ok, answer: output, explanation: "Answer: #{output.to_json}", code:)
    rescue Boxcars::SecurityError => e
      raise e
    rescue StandardError => e
      Result.new(status: :error, answer: nil, explanation: "Error: #{e.message}", code:)
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
      @conversation ||= Conversation.new(lines: CTEMPLATE)
      @my_prompt ||= ConversationPrompt.new(
        conversation: @conversation,
        input_variables: [:question],
        other_inputs: [:top_k, :dialect, :schema, :context],
        output_variables: [:answer])
    end
  end
end
