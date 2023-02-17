# frozen_string_literal: true

require_relative "lib/boxcars/version"

Gem::Specification.new do |spec|
  spec.name = "boxcars"
  spec.version = Boxcars::VERSION
  spec.authors = ["Francis Sullivan", "Tabrez Syed"]
  spec.email = ["hi@boxcars.ai"]

  spec.summary = "Boxcars provide an API to connect together Boxcars and then conduct them. Inspired by python langchain."
  spec.description = "You simply give a number of boxcars to a train, and it does the magic."
  spec.homepage = "https://github.com/BoxcarsAI/boxcars"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://github.com/BoxcarsAI/boxcars/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:test|spec|features|notebooks)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # dev / test dependencies
  spec.add_development_dependency "debug", "~> 1.1"
  spec.add_development_dependency "dotenv", "~> 2.8"
  spec.add_development_dependency "rspec", "~> 3.2"

  # runtime dependencies
  spec.add_dependency "google_search_results", "~> 2.2"
  spec.add_dependency "ruby-openai", "~> 3.0"

  # For more information and examples about making a new gem, checkout our
  # guide at: https://bundler.io/guides/creating_gem.html
end
