# frozen_string_literal: true

RSpec.describe Gem::Specification do
  subject(:required_ruby_version) do
    described_class.load(File.expand_path("../../boxcars.gemspec", __dir__)).required_ruby_version
  end

  it "supports Ruby 3.3 and later" do
    expect(required_ruby_version).to be_satisfied_by(Gem::Version.new("3.3.0"))
  end

  it "does not support Ruby 3.2" do
    expect(required_ruby_version).not_to be_satisfied_by(Gem::Version.new("3.2.9"))
  end
end
