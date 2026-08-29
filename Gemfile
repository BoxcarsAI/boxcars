# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in boxcars.gemspec
gemspec

gem "dotenv", "~> 3.1"
gem "rake", "~> 13.2"
gem "sqlite3", "~> 2.0"
gem "activerecord", "~> 8.1"
gem "activesupport", "~> 8.1"
gem "pg", "~> 1.5"
gem "pgvector", "~> 0.3.2"

group :development, :test do
  # Optional runtime provider/tooling gems kept here for local development + CI.
  # openai 0.76+ requires Ruby 3.3; keep CI installable at the gem's Ruby 3.2 floor.
  gem "openai", ">= 0.30", "< 0.76"
  gem "faraday", "~> 2.0"
  gem "google_search_results", "~> 2.2"
  gem "hnswlib", "~> 0.9.0"
  gem "nokogiri", "~> 1.18"
  gem "sequel", "~> 5.106"
  gem "ruby-anthropic", "~> 0.4"
  gem "debug", "~> 1.9"
  # RDoc 8 pulls RBS 4, which requires Ruby 3.3 and breaks the Ruby 3.2 CI lane.
  gem "rdoc", "< 8", require: false
  gem "rspec", "~> 3.13"
  gem "rubocop", "~> 1.88"
  # parallel 2.0+ requires Ruby 3.3.
  gem "parallel", "< 2", require: false
  gem "vcr", "~> 6.4.0"
  gem "webmock", "~> 3.26.1"
  gem "rubocop-rake", "~> 0.7.1"
  gem "rubocop-rspec", "~> 3.2"
  gem "posthog-ruby", require: false
end
