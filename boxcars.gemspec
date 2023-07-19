# frozen_string_literal: true

require_relative "lib/boxcars/version"

Gem::Specification.new do |spec|
  spec.name = "boxcars"
  spec.version = Boxcars::VERSION
  spec.authors = ["Francis Sullivan", "Tabrez Syed"]
  spec.email = ["hi@boxcars.ai"]

  spec.summary = "Boxcars is a gem that enables you to create new systems with AI composability. Inspired by python langchain."
  spec.description = "You simply set an OpenAI key, give a number of Boxcars to a Train, and magic ensues when you run it."
  spec.homepage = "https://github.com/BoxcarsAI/boxcars"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

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

  # runtime dependencies
  spec.add_dependency "anthropic", "~> 0.1"
  spec.add_dependency "google_search_results", "~> 2.2"
  spec.add_dependency "gpt4all", "~> 0.0.4"
  spec.add_dependency "hnswlib", "~> 0.8"
  spec.add_dependency "nokogiri", "~> 1.15"
  spec.add_dependency "pgvector", "~> 0.2"
  spec.add_dependency "ruby-openai", "~> 4.1"

  # For more information and examples about making a new gem, checkout our
  # guide at: https://bundler.io/guides/creating_gem.html
end
