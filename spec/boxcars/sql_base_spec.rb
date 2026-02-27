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

  it "raises a table-not-found error (not NoMethodError) when explicit tables are passed without a connection table list" do
    expect do
      dummy_sql_boxcar_class.new(connection: nil, tables: ["users"])
    end.to raise_error(Boxcars::ArgumentError, /table users not found in database/)
  end
end
