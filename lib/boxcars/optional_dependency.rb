# frozen_string_literal: true

module Boxcars
  # Helper for feature-gated dependencies that are not required for core runtime.
  module OptionalDependency
    @loaded = {}

    def self.require!(gem_name, feature:)
      return true if @loaded[gem_name]

      require gem_name
      @loaded[gem_name] = true
      true
    rescue LoadError
      raise Boxcars::ConfigurationError,
            "#{feature} requires the optional gem '#{gem_name}'. " \
            "Add `gem \"#{gem_name}\"` to your Gemfile."
    end
  end
end
