# Changelog

## [v0.3.1](https://github.com/BoxcarsAI/boxcars/tree/v0.3.1) (2023-07-01)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.16...v0.3.1)

**Closed issues:**

- Add a running log of prompts for debugging [\#99](https://github.com/BoxcarsAI/boxcars/issues/99)
- Anyway to create conversation? [\#73](https://github.com/BoxcarsAI/boxcars/issues/73)

**Merged pull requests:**

- now, when you call run on a train multiple times, it remembers the ru… [\#101](https://github.com/BoxcarsAI/boxcars/pull/101) ([francis](https://github.com/francis))

## [v0.2.16](https://github.com/BoxcarsAI/boxcars/tree/v0.2.16) (2023-06-26)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.15...v0.2.16)

**Implemented enhancements:**

- Support Sequel connection type [\#22](https://github.com/BoxcarsAI/boxcars/issues/22)

**Closed issues:**

- Using the SQL model This model's maximum context length is 4097 tokens [\#88](https://github.com/BoxcarsAI/boxcars/issues/88)

**Merged pull requests:**

- Add running logs [\#100](https://github.com/BoxcarsAI/boxcars/pull/100) ([francis](https://github.com/francis))
- create new Sequel boxcar, and refactor Active Record SQL boxcar [\#98](https://github.com/BoxcarsAI/boxcars/pull/98) ([francis](https://github.com/francis))
- Support for Sequel SQL connection types [\#97](https://github.com/BoxcarsAI/boxcars/pull/97) ([eltoob](https://github.com/eltoob))

## [v0.2.15](https://github.com/BoxcarsAI/boxcars/tree/v0.2.15) (2023-06-09)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.14...v0.2.15)

**Merged pull requests:**

- make suggested next actions optional [\#94](https://github.com/BoxcarsAI/boxcars/pull/94) ([francis](https://github.com/francis))

## [v0.2.14](https://github.com/BoxcarsAI/boxcars/tree/v0.2.14) (2023-06-06)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.13...v0.2.14)

**Closed issues:**

- VectorAnswer always return error "Query must a string" [\#90](https://github.com/BoxcarsAI/boxcars/issues/90)
- Readme vector search example 404 [\#86](https://github.com/BoxcarsAI/boxcars/issues/86)
- Add Boxcar similar to LLMChain [\#85](https://github.com/BoxcarsAI/boxcars/issues/85)

**Merged pull requests:**

- Chore/refactored vector stores [\#92](https://github.com/BoxcarsAI/boxcars/pull/92) ([jaigouk](https://github.com/jaigouk))
- Fix the issue of calling the wrong method in vector\_answer.rb. [\#91](https://github.com/BoxcarsAI/boxcars/pull/91) ([xleotranx](https://github.com/xleotranx))
- issue\_83 Fix readme 404 [\#87](https://github.com/BoxcarsAI/boxcars/pull/87) ([beouk](https://github.com/beouk))

## [v0.2.13](https://github.com/BoxcarsAI/boxcars/tree/v0.2.13) (2023-05-24)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.12...v0.2.13)

**Closed issues:**

- Typo "Boscar.error" should be "Boxcars.error" [\#82](https://github.com/BoxcarsAI/boxcars/issues/82)

**Merged pull requests:**

- Add vector answer boxcar [\#79](https://github.com/BoxcarsAI/boxcars/pull/79) ([francis](https://github.com/francis))

## [v0.2.12](https://github.com/BoxcarsAI/boxcars/tree/v0.2.12) (2023-05-22)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.11...v0.2.12)

**Closed issues:**

- GPT-4 support? [\#71](https://github.com/BoxcarsAI/boxcars/issues/71)
- add PgVector Vector Store [\#68](https://github.com/BoxcarsAI/boxcars/issues/68)

**Merged pull requests:**

- issue\_82 typo "Boscar" instead of "Boxcars" [\#83](https://github.com/BoxcarsAI/boxcars/pull/83) ([MadBomber](https://github.com/MadBomber))
- Update boxcars.rb config example [\#81](https://github.com/BoxcarsAI/boxcars/pull/81) ([nhorton](https://github.com/nhorton))
- Feature- added pgvector vector store [\#80](https://github.com/BoxcarsAI/boxcars/pull/80) ([jaigouk](https://github.com/jaigouk))
- drop support for pre ruby 3 version [\#75](https://github.com/BoxcarsAI/boxcars/pull/75) ([francis](https://github.com/francis))
- Chore - refine VectorSearch [\#74](https://github.com/BoxcarsAI/boxcars/pull/74) ([jaigouk](https://github.com/jaigouk))
- raise error if OpenAI API returns error or nil. closes \#71 [\#72](https://github.com/BoxcarsAI/boxcars/pull/72) ([francis](https://github.com/francis))

## [v0.2.11](https://github.com/BoxcarsAI/boxcars/tree/v0.2.11) (2023-05-05)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.10...v0.2.11)

**Closed issues:**

- Chore: move vector store to top level [\#67](https://github.com/BoxcarsAI/boxcars/issues/67)

**Merged pull requests:**

- Move vector store [\#69](https://github.com/BoxcarsAI/boxcars/pull/69) ([francis](https://github.com/francis))

## [v0.2.10](https://github.com/BoxcarsAI/boxcars/tree/v0.2.10) (2023-05-05)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.9...v0.2.10)

**Implemented enhancements:**

- Notion Q&A [\#13](https://github.com/BoxcarsAI/boxcars/issues/13)

**Closed issues:**

- undefined method `default\_train' for Boxcars:Module \(ActiveRecord example\) [\#66](https://github.com/BoxcarsAI/boxcars/issues/66)
- Chore: reduce the number of markdown files in Notion DB folder [\#56](https://github.com/BoxcarsAI/boxcars/issues/56)

**Merged pull requests:**

- \[DRAFT\] Feature - add in memory vector store [\#65](https://github.com/BoxcarsAI/boxcars/pull/65) ([jaigouk](https://github.com/jaigouk))
- Chore - rename module name from Embeddings to VectorStores [\#63](https://github.com/BoxcarsAI/boxcars/pull/63) ([jaigouk](https://github.com/jaigouk))
- remove bunch of markdown files in Notion\_DB directory [\#62](https://github.com/BoxcarsAI/boxcars/pull/62) ([jaigouk](https://github.com/jaigouk))
- Fixed typo in README.md [\#61](https://github.com/BoxcarsAI/boxcars/pull/61) ([robmack](https://github.com/robmack))

## [v0.2.9](https://github.com/BoxcarsAI/boxcars/tree/v0.2.9) (2023-04-22)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.8...v0.2.9)

**Closed issues:**

- Getting started docs out of date [\#58](https://github.com/BoxcarsAI/boxcars/issues/58)

**Merged pull requests:**

- add default openai client, and new notebook [\#59](https://github.com/BoxcarsAI/boxcars/pull/59) ([francis](https://github.com/francis))

## [v0.2.8](https://github.com/BoxcarsAI/boxcars/tree/v0.2.8) (2023-04-19)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.7...v0.2.8)

**Closed issues:**

- Getting the same verbosity as in the examples [\#54](https://github.com/BoxcarsAI/boxcars/issues/54)

**Merged pull requests:**

- Add Engine for Gpt4all [\#55](https://github.com/BoxcarsAI/boxcars/pull/55) ([francis](https://github.com/francis))
- update google search to return URL for result if present [\#53](https://github.com/BoxcarsAI/boxcars/pull/53) ([francis](https://github.com/francis))
- Draft: added gpt4all [\#49](https://github.com/BoxcarsAI/boxcars/pull/49) ([jaigouk](https://github.com/jaigouk))
- Embeddings with hnswlib [\#48](https://github.com/BoxcarsAI/boxcars/pull/48) ([jaigouk](https://github.com/jaigouk))

## [v0.2.7](https://github.com/BoxcarsAI/boxcars/tree/v0.2.7) (2023-04-13)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.5...v0.2.7)

**Closed issues:**

- The class name in the sample code of BoxCar-Google-Search wiki has not been changed. [\#50](https://github.com/BoxcarsAI/boxcars/issues/50)

**Merged pull requests:**

- Add Swagger Boxcar [\#51](https://github.com/BoxcarsAI/boxcars/pull/51) ([francis](https://github.com/francis))
- Boxcars::SQL tables and except\_tables [\#47](https://github.com/BoxcarsAI/boxcars/pull/47) ([arihh](https://github.com/arihh))
- ActiveRecord updates and new Wikipedia Search boxcar [\#46](https://github.com/BoxcarsAI/boxcars/pull/46) ([francis](https://github.com/francis))
- Fix README.md log\_prompts settings [\#45](https://github.com/BoxcarsAI/boxcars/pull/45) ([arihh](https://github.com/arihh))
- Update README.md to use the GoogleSearch Boxcar [\#44](https://github.com/BoxcarsAI/boxcars/pull/44) ([stockandawe](https://github.com/stockandawe))

## [v0.2.5](https://github.com/BoxcarsAI/boxcars/tree/v0.2.5) (2023-03-30)

[Full Changelog](https://github.com/BoxcarsAI/boxcars/compare/v0.2.4...v0.2.5)

**Merged pull requests:**

- switch to safe level 4 for eval, and rerun tests [\#43](https://github.com/BoxcarsAI/boxcars/pull/43) ([francis](https://github.com/francis))

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
