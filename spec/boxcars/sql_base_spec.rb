# frozen_string_literal: true

require "spec_helper"

RSpec.describe Boxcars::SQLBase do
  let(:dummy_sql_boxcar_class) do
    Class.new(described_class) do
      private

      def table_schema(table)
        "CREATE TABLE #{table} (...)"
      end

      def dialect
        "sqlite"
      end

      def get_output(_code)
        []
      end
    end
  end

  let(:connection) { double("Connection", tables: []) } # rubocop:disable RSpec/VerifiedDoubles

  it "raises a table-not-found error (not NoMethodError) when explicit tables are passed without a connection table list" do
    expect do
      dummy_sql_boxcar_class.new(connection: nil, tables: ["users"])
    end.to raise_error(Boxcars::ArgumentError, /table users not found in database/)
  end

  it "declares :context as a prompt dependency" do
    boxcar = dummy_sql_boxcar_class.new(connection:)
    expect(boxcar.prompt.other_inputs).to include(:context)
  end

  it "includes context text in prompt when provided" do
    boxcar = dummy_sql_boxcar_class.new(connection:, context: "Tenant ID is 5.")
    additional = boxcar.prediction_additional({})
    expect(additional[:context]).to include("Tenant ID is 5.")
    expect(additional[:context]).to include("Additional context:")
  end

  it "produces empty string when context is nil" do
    boxcar = dummy_sql_boxcar_class.new(connection:)
    additional = boxcar.prediction_additional({})
    expect(additional[:context]).to eq("")
  end

  it "declares :schema as a prompt dependency (not legacy :table_info)" do
    boxcar = dummy_sql_boxcar_class.new(connection:)

    expect(boxcar.prompt.other_inputs).to include(:schema)
    expect(boxcar.prompt.other_inputs).not_to include(:table_info)
  end

  describe "read-only mode" do
    context "with default settings" do
      let(:boxcar) { dummy_sql_boxcar_class.new(connection:) }

      it "defaults to read_only true" do
        expect(boxcar).to be_read_only
      end

      it "allows SELECT queries" do
        expect(boxcar.send(:sql_safe_to_run?, "SELECT * FROM users")).to be true
      end

      it "allows EXPLAIN queries" do
        expect(boxcar.send(:sql_safe_to_run?, "EXPLAIN SELECT * FROM users")).to be true
      end

      it "allows SHOW queries" do
        expect(boxcar.send(:sql_safe_to_run?, "SHOW TABLES")).to be true
      end

      it "allows WITH (CTE) queries" do
        expect(boxcar.send(:sql_safe_to_run?, "WITH cte AS (SELECT 1) SELECT * FROM cte")).to be true
      end

      it "rejects INSERT" do
        expect(boxcar.send(:sql_safe_to_run?, "INSERT INTO users (name) VALUES ('bob')")).to be false
      end

      it "rejects UPDATE" do
        expect(boxcar.send(:sql_safe_to_run?, "UPDATE users SET name = 'bob'")).to be false
      end

      it "rejects DELETE" do
        expect(boxcar.send(:sql_safe_to_run?, "DELETE FROM users WHERE id = 1")).to be false
      end

      it "rejects DROP" do
        expect(boxcar.send(:sql_safe_to_run?, "DROP TABLE users")).to be false
      end

      it "rejects ALTER" do
        expect(boxcar.send(:sql_safe_to_run?, "ALTER TABLE users ADD COLUMN age INT")).to be false
      end

      it "rejects CREATE" do
        expect(boxcar.send(:sql_safe_to_run?, "CREATE TABLE evil (id INT)")).to be false
      end

      it "rejects TRUNCATE" do
        expect(boxcar.send(:sql_safe_to_run?, "TRUNCATE TABLE users")).to be false
      end
    end

    context "with string literals containing write keywords" do
      let(:boxcar) { dummy_sql_boxcar_class.new(connection:) }

      it "does not false-positive on DELETE inside a string literal" do
        expect(boxcar.send(:sql_safe_to_run?, "SELECT * FROM users WHERE name = 'DELETE ME'")).to be true
      end

      it "does not false-positive on INSERT inside a string literal" do
        expect(boxcar.send(:sql_safe_to_run?, "SELECT * FROM logs WHERE action = 'INSERT record'")).to be true
      end

      it "does not false-positive on UPDATE inside a string literal" do
        expect(boxcar.send(:sql_safe_to_run?, "SELECT * FROM events WHERE type = 'UPDATE'")).to be true
      end
    end

    context "when get_embedded_sql_answer encounters write SQL in read-only mode" do
      let(:boxcar) { dummy_sql_boxcar_class.new(connection:) }

      it "raises Boxcars::SecurityError" do
        expect do
          boxcar.send(:get_embedded_sql_answer, "SQLQuery: DELETE FROM users WHERE id = 1")
        end.to raise_error(Boxcars::SecurityError, /Permission to execute write SQL denied/)
      end

      it "does not raise for SELECT queries" do
        expect do
          boxcar.send(:get_embedded_sql_answer, "SQLQuery: SELECT * FROM users")
        end.not_to raise_error
      end
    end

    context "with approval_callback" do
      it "defaults read_only to false when approval_callback is provided" do
        callback = proc { |_sql| true }
        boxcar = dummy_sql_boxcar_class.new(connection:, approval_callback: callback)
        expect(boxcar).not_to be_read_only
      end

      it "calls the approval_callback with the SQL string for write queries" do
        received_sql = nil
        callback = proc do |sql|
          received_sql = sql
          true
        end
        boxcar = dummy_sql_boxcar_class.new(connection:, approval_callback: callback)
        boxcar.send(:approved?, "DELETE FROM users WHERE id = 1")
        expect(received_sql).to eq("DELETE FROM users WHERE id = 1")
      end

      it "does not call the approval_callback for safe read queries" do
        callback_called = false
        callback = proc do |_sql|
          callback_called = true
          true
        end
        boxcar = dummy_sql_boxcar_class.new(connection:, approval_callback: callback)
        boxcar.send(:approved?, "SELECT * FROM users")
        expect(callback_called).to be false
      end

      it "raises SecurityError when approval_callback returns false" do
        callback = proc { |_sql| false }
        boxcar = dummy_sql_boxcar_class.new(connection:, approval_callback: callback)
        expect do
          boxcar.send(:get_embedded_sql_answer, "SQLQuery: INSERT INTO users (name) VALUES ('bob')")
        end.to raise_error(Boxcars::SecurityError, /Permission to execute write SQL denied/)
      end
    end

    context "with explicit read_only: false" do
      let(:boxcar) { dummy_sql_boxcar_class.new(connection:, read_only: false) }

      it "allows write SQL without a callback" do
        expect(boxcar.send(:approved?, "DELETE FROM users WHERE id = 1")).to be true
      end

      it "is not read_only" do
        expect(boxcar).not_to be_read_only
      end
    end

    context "with explicit read_only: true and approval_callback" do
      it "enforces read_only even when a callback is provided" do
        callback = proc { |_sql| true }
        boxcar = dummy_sql_boxcar_class.new(connection:, read_only: true, approval_callback: callback)
        expect(boxcar).to be_read_only
        expect(boxcar.send(:approved?, "DELETE FROM users")).to be false
      end
    end
  end
end
