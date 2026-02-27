# frozen_string_literal: true

require "spec_helper"

RSpec.describe "SQL optional dependency wiring" do
  it "raises setup guidance when active_record gem is missing for SQLActiveRecord" do
    allow(Boxcars::OptionalDependency).to receive(:require!)
      .with("activerecord", feature: "Boxcars::SQLActiveRecord", require_as: "active_record")
      .and_raise(Boxcars::ConfigurationError, "Missing optional dependency 'activerecord'.")

    expect do
      Boxcars::SQLActiveRecord.new
    end.to raise_error(Boxcars::ConfigurationError, /optional dependency 'activerecord'/)
  end

  it "raises setup guidance when active_record gem is missing for ActiveRecord boxcar" do
    allow(Boxcars::OptionalDependency).to receive(:require!)
      .with("activerecord", feature: "Boxcars::ActiveRecord", require_as: "active_record")
      .and_raise(Boxcars::ConfigurationError, "Missing optional dependency 'activerecord'.")

    expect do
      Boxcars::ActiveRecord.new(models: [])
    end.to raise_error(Boxcars::ConfigurationError, /optional dependency 'activerecord'/)
  end

  it "raises setup guidance when sequel gem is missing for SQLSequel" do
    allow(Boxcars::OptionalDependency).to receive(:require!)
      .with("sequel", feature: "Boxcars::SQLSequel")
      .and_raise(Boxcars::ConfigurationError, "Missing optional dependency 'sequel'.")

    expect do
      Boxcars::SQLSequel.new
    end.to raise_error(Boxcars::ConfigurationError, /optional dependency 'sequel'/)
  end
end
