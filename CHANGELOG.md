# Changelog

## [v0.2.4](https://github.com/BoxcarsAI/boxcars/tree/v0.2.4) (2023-03-28)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.3...v0.2.4)

**Closed issues:**

- security [\#40](https://github.com/BoxcarsAI/boxcars/issues/40)

**Merged pull requests:**

- Fix regex action input [\#41](https://github.com/BoxcarsAI/boxcars/pull/41) ([makevoid](https://github.com/makevoid))

## [v0.2.3](https://github.com/BoxcarsAI/boxcars/tree/v0.2.3) (2023-03-20)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.2...v0.2.3)

**Merged pull requests:**

- better error handling and retry for Active Record Boxcar [\#39](https://github.com/BoxcarsAI/boxcars/pull/39) ([francis](https://github.com/francis))

## [v0.2.2](https://github.com/BoxcarsAI/boxcars/tree/v0.2.2) (2023-03-16)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.1...v0.2.2)

**Implemented enhancements:**

- return a structure from boxcars instead of just a string [\#31](https://github.com/BoxcarsAI/boxcars/issues/31)
- modify SQL boxcar to take a list of Tables. Handy if you have a large database with many tables. [\#19](https://github.com/BoxcarsAI/boxcars/issues/19)

**Closed issues:**

- make a new type of prompt that uses conversations [\#38](https://github.com/BoxcarsAI/boxcars/issues/38)
- Add test coverage [\#8](https://github.com/BoxcarsAI/boxcars/issues/8)

## [v0.2.1](https://github.com/BoxcarsAI/boxcars/tree/v0.2.1) (2023-03-08)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.0...v0.2.1)

**Implemented enhancements:**

- add the ability to use the ChatGPT API - a ChatGPT Boxcar::Engine [\#32](https://github.com/BoxcarsAI/boxcars/issues/32)
- Prompt simplification [\#29](https://github.com/BoxcarsAI/boxcars/issues/29)

**Merged pull requests:**

- use structured results internally and bring SQL up to parity with ActiveRecord boxcar. [\#36](https://github.com/BoxcarsAI/boxcars/pull/36) ([francis](https://github.com/francis))

## [v0.2.0](https://github.com/BoxcarsAI/boxcars/tree/v0.2.0) (2023-03-07)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.1.8...v0.2.0)

**Merged pull requests:**

- Default to chatgpt [\#35](https://github.com/BoxcarsAI/boxcars/pull/35) ([francis](https://github.com/francis))

## [v0.1.8](https://github.com/BoxcarsAI/boxcars/tree/v0.1.8) (2023-03-02)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.1.7...v0.1.8)

**Merged pull requests:**

- return JSON from the Active Record boxcar [\#34](https://github.com/BoxcarsAI/boxcars/pull/34) ([francis](https://github.com/francis))
- validate return values from Open AI API [\#33](https://github.com/BoxcarsAI/boxcars/pull/33) ([francis](https://github.com/francis))
- simplify prompting and parameters used. refs \#29 [\#30](https://github.com/BoxcarsAI/boxcars/pull/30) ([francis](https://github.com/francis))
- \[infra\] Added sample .env file and updated the lookup to save the key [\#27](https://github.com/BoxcarsAI/boxcars/pull/27) ([AKovtunov](https://github.com/AKovtunov))

## [v0.1.7](https://github.com/BoxcarsAI/boxcars/tree/v0.1.7) (2023-02-27)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.1.6...v0.1.7)

**Implemented enhancements:**

- figure out logging [\#10](https://github.com/BoxcarsAI/boxcars/issues/10)

**Merged pull requests:**

- Fix typos in README concepts [\#26](https://github.com/BoxcarsAI/boxcars/pull/26) ([MasterOdin](https://github.com/MasterOdin))

## [v0.1.6](https://github.com/BoxcarsAI/boxcars/tree/v0.1.6) (2023-02-24)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.1.5...v0.1.6)

**Implemented enhancements:**

- Add a callback function for Boxcars::ActiveRecord to approve changes  [\#24](https://github.com/BoxcarsAI/boxcars/issues/24)

**Merged pull requests:**

- Add approval callback function for Boxcars::ActiveRecord for changes to the data [\#25](https://github.com/BoxcarsAI/boxcars/pull/25) ([francis](https://github.com/francis))
- \[fix\] Fixed specs which required a key [\#23](https://github.com/BoxcarsAI/boxcars/pull/23) ([AKovtunov](https://github.com/AKovtunov))

## [v0.1.5](https://github.com/BoxcarsAI/boxcars/tree/v0.1.5) (2023-02-22)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.1.4...v0.1.5)

**Implemented enhancements:**

- Make Boxcars::ActiveRecord read\_only by default [\#20](https://github.com/BoxcarsAI/boxcars/issues/20)

**Merged pull requests:**

- Active Record readonly [\#21](https://github.com/BoxcarsAI/boxcars/pull/21) ([francis](https://github.com/francis))

## [v0.1.4](https://github.com/BoxcarsAI/boxcars/tree/v0.1.4) (2023-02-22)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.1.3...v0.1.4)

**Implemented enhancements:**

- Extend Sql concept to produce and run ActiveRecord code instead of SQL [\#9](https://github.com/BoxcarsAI/boxcars/issues/9)

**Merged pull requests:**

- first pass at an ActiveRecord boxcar [\#18](https://github.com/BoxcarsAI/boxcars/pull/18) ([francis](https://github.com/francis))
- change Boxcars::default\_train to Boxcars::train to improve code reada… [\#17](https://github.com/BoxcarsAI/boxcars/pull/17) ([francis](https://github.com/francis))
- rename class Serp to GoogleSearch [\#16](https://github.com/BoxcarsAI/boxcars/pull/16) ([francis](https://github.com/francis))
- Update README.md [\#15](https://github.com/BoxcarsAI/boxcars/pull/15) ([tabrez-syed](https://github.com/tabrez-syed))

## [v0.1.3](https://github.com/BoxcarsAI/boxcars/tree/v0.1.3) (2023-02-17)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.1.2...v0.1.3)

**Closed issues:**

- generate changelog automatically [\#12](https://github.com/BoxcarsAI/boxcars/issues/12)
- Make sure the yard docs are up to date and have coverage [\#7](https://github.com/BoxcarsAI/boxcars/issues/7)
- Name changes and code movement. [\#6](https://github.com/BoxcarsAI/boxcars/issues/6)
- Specs need environment variables to be set to run green [\#4](https://github.com/BoxcarsAI/boxcars/issues/4)

**Merged pull requests:**

- Get GitHub Actions to green [\#5](https://github.com/BoxcarsAI/boxcars/pull/5) ([petergoldstein](https://github.com/petergoldstein))
- Fix typo introduced by merge.  Pull publish-rubygem into its own job [\#3](https://github.com/BoxcarsAI/boxcars/pull/3) ([petergoldstein](https://github.com/petergoldstein))

## [v0.1.2](https://github.com/BoxcarsAI/boxcars/tree/v0.1.2) (2023-02-17)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.1.1...v0.1.2)

**Merged pull requests:**

- Run GitHub Actions against multiple Rubies [\#2](https://github.com/BoxcarsAI/boxcars/pull/2) ([petergoldstein](https://github.com/petergoldstein))
- \[infra\] Added deployment step for the RubyGems [\#1](https://github.com/BoxcarsAI/boxcars/pull/1) ([AKovtunov](https://github.com/AKovtunov))

## [v0.1.1](https://github.com/BoxcarsAI/boxcars/tree/v0.1.1) (2023-02-16)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.1.0...v0.1.1)

## [v0.1.0](https://github.com/BoxcarsAI/boxcars/tree/v0.1.0) (2023-02-15)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/e3c50bdc76f71c6d2abb012c38174633a5847028...v0.1.0)



\* *This Changelog was automatically generated by [github_changelog_generator](https://github.com/github-changelog-generator/github-changelog-generator)*
