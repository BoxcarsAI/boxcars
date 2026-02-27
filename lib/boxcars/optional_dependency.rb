# frozen_string_literal: true

module Boxcars
  # Helper for feature-gated dependencies that are not required for core runtime.
  module OptionalDependency
    @loaded = {}

    def self.require!(gem_name, feature:, require_as: gem_name)
      cache_key = "#{gem_name}:#{require_as}"
      return true if @loaded[cache_key]

      require require_as
      @loaded[cache_key] = true
      true
    rescue LoadError
      raise Boxcars::ConfigurationError,
            "#{feature} requires the optional gem '#{gem_name}'. " \
            "Add `gem \"#{gem_name}\"` to your Gemfile."
    end
  end
end
