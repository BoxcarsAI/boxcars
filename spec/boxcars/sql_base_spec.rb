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

  it "declares :schema as a prompt dependency (not legacy :table_info)" do
    connection = instance_double("Connection", tables: [])
    boxcar = dummy_sql_boxcar_class.new(connection:)

    expect(boxcar.prompt.other_inputs).to include(:schema)
    expect(boxcar.prompt.other_inputs).not_to include(:table_info)
  end
end
