# Boxcars

This gem lets you compose new systems with composability using systems like OpenAI, Search, and SQL (and many more).

The popular python library langchain is a precursor to this work, but we wanted to put a ruby spin on things and make it easier to get started.

## Concepts
All of these concepts are in a module named Boxcars:
- Prompt: a prompt is used by an Engine to generate text results.
- Engine: an entity that generates text from a Prompt.
- Boxcar: an encapsulation that does one thing (search, math, SQL, etc) and a many use an Engine to get their work accomplished.
- Conductor: given a list of Boxcars and an Engine, an answer if found by breaking the promlem into peices for an indvidual Boxcar to solve. This is all joined back together to yield a final result. There is currently only one implementation - ZeroShot. You can construct it directly, or just use `Boxcars::default_conductor`

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
require "boxcars"
```

### Direct Boxcar Use

```ruby
# run the calculator
engine = Boxcars::Openai.new(max_tokens: 256)
calc = Boxcars::Calculator.new(engine: engine)
puts calc.run "what is pi to the forth power divided by 22.1?"
```
This segment above (try it by pasting into an `irb` session)
```text
> Enterning Calculator boxcar#run
what is pi to the forth power divided by 22.1?
RubyREPL: puts(Math::PI**4 / 22.1)
Answer: 4.407651178009159

4.407651178009159
< Exiting Calculator boxcar#run
4.407651178009159
```

Note that since Openai is currently the most used Engine, if you do not pass in an engine, it will default as expected. So, this is the equialent shorter version of the above script:
```ruby
# run the calculator
calc = Boxcars::Calculator.new # just use the default Engine
puts calc.run "what is pi to the forth power divided by 22.1?"
```
### Boxcars currently implemmented

Here is what we have so far, but please put up a PR with your new ideas.
- Search: uses the SERP API to do seaches
- Calculator: uses an Engine to generate ruby code to do math
- SQL: given an ActiveRecord connection, it will generate and run sql statments from a prompt.

### Run a list of Boxcars
```ruby
# run a Conductor for a calculator, and search using default Engine
boxcars = [Boxcars::Calculator.new, Boxcars::Serp.new]
cond = Boxcars.default_conductor.new(boxcars: boxcars)
puts cond.run "What is pi times the square root of the average temperature in Austin TX in January?"
```
This outputs:
```text
> Enterning Zero Shot boxcar#run
What is pi times the square root of the average temperature in Austin TX in January?
Question: Average temperature in Austin TX in January
Answer: increase from 62°F to 64°F
#Observation: increase from 62°F to 64°F
> Enterning Calculator boxcar#run
64°F x pi
RubyREPL: puts (64 * Math::PI).round(2)
Answer: 201.06

201.06
< Exiting Calculator boxcar#run
#Observation: 201.06
I now know the final answer
Final Answer: 201.06
< Exiting Zero Shot boxcar#run
201.06
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
