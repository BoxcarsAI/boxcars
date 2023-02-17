# Boxcars

This gem lets you compose new systems with composability using systems like OpenAI, Search, and SQL (and many more).

The popular python library langchain is a precursor to this work, but we wanted to put a ruby spin on things and make it easier to get started.

## Concepts
All of these concepts are in a module named Boxcars:
- Prompt: a prompt is used by an Engine to generate text results.
- Engine: an entity that generates text from a Prompt.
- Boxcar: an encapsulation that does one thing (search, math, SQL, etc) and a many use an Engine to get their work accomplished.
- Conductor: given a list of Boxcars and an Engine, an answer if found by breaking the promlem into peices for an indvidual Boxcar to solve. This is all joined back together to yield a final result. There is currently only one implementation - ZeroShot.
- ConductorExecutor: manages the running of a Conductor.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'boxcars'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install boxcars

## Usage

We will document many more examples soon, but here are a couple. The first step is to setup your environment variables for OpenAI and Serp (OPENAI_ACCESS_TOKEN, SERPAPI_API_KEY). If you don't want to set them in your environment, they can be passed in as well to the API.

In the examples below, we added one rubygem to load the environment at the first line, but depending on what you want, you might not need this.
```ruby
require "dotenv/load"
```

### Direct Boxcar Use

```ruby
# run the calculator
require "dotenv/load"
require "boxcars"

engine = Boxcars::Openai.new
calc = Boxcars::Calculator.new(engine: engine)
puts calc.run "what is pi to the forth power divided by 22.1?"
```

### Boxcars currently implemmented

Here is what we have so far, but please put up a PR with your new ideas.
- Search: uses the SERP API to do seaches
- Calculator: uses an Engine to generate ruby code to do math
- SQL: given an ActiveRecord connection, it will generate and run sql statments from a prompt.

### Run a list of Boxcars
```ruby
# run a Conductor for a calculator, and search 
require "dotenv/load"
require "boxcars"

engine = Boxcars::Openai.new
calc = Boxcars::Calculator.new(engine: engine)
search = Boxcars::Serp.new
cond = Boxcars::ZeroShot.new(engine: engine, boxcars: [calc, search])
cexe = Boxcars::ConductorExecuter.new(conductor: cond)
puts cexe.run "What is pi times the square root of the average temperature in Austin TX in January?"
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/boxcars. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/[USERNAME]/boxcars/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Boxcars project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/boxcars/blob/main/CODE_OF_CONDUCT.md).
