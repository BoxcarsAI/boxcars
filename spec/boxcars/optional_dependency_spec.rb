# frozen_string_literal: true

require "spec_helper"

RSpec.describe Boxcars::OptionalDependency do
  describe ".require!" do
    it "loads installed optional gems" do
      expect(described_class.require!("json", feature: "test feature")).to eq(true)
    end

    it "raises a setup error when the optional gem is missing" do
      expect do
        described_class.require!("definitely_missing_boxcars_optional_gem", feature: "test feature")
      end.to raise_error(Boxcars::ConfigurationError, /test feature requires the optional gem/)
    end

    it "supports a distinct gem name and require path" do
      expect do
        described_class.require!(
          "activerecord",
          feature: "test feature",
          require_as: "definitely_missing_require_path"
        )
      end.to raise_error(Boxcars::ConfigurationError, /optional gem 'activerecord'/)
    end
  end
end
