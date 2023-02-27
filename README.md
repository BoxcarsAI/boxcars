<h2 align="center">Boxcars</h2>

<h4 align="center">
  <a href="https://www.boxcars.ai">Website</a> |
  <a href="https://www.boxcars.ai/roadmap">Roadmap</a> |
  <a href="https://www.boxcars.ai/blog">Blog</a> |
  <a href="https://github.com/BoxcarsAI/boxcars/wiki">Documentation</a> 
</h4>

<p align="center">
  <a href="https://github.com/BoxcarsAI/boxcars/blob/main/LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-informational" alt="License"></a>
</p>

Boxcars is a gem that enables you to create new systems with AI composability, using various concepts such as OpenAI, Search, SQL, Rails Active Record and more. This can even be extended with your concepts as well.(including your concepts).

This gem was inspired by the popular Python library Langchain. However, we wanted to give it a Ruby spin and make it more user-friendly for beginners to get started.

## Concepts
All of these concepts are in a module named Boxcars:

- Boxcar - an encapsulation that performs something of interest (such as search, math, SQL or an Active Record Query). A Boxcar can use an Engine (described below) to do its work.
- Train - Given a list of Boxcars and optionally an Engine, a Train breaks down a problem into pieces for individual Boxcars to solve. The individual results are then combined until a final answer is found. ZeroShot is the only current implementation of Train (but we are adding more soon), and you can either construct it directly or use `Boxcars::train` when you want to build a Train.
- Prompt - used by an Engine to generate text results. Most of the Boxcars have built-in prompts, so you only need to worry about these if you are extending the system.
- Engine - an entity that generates text from a Prompt. OpenAI's LLM text generator is the default Engine if no other is specified.

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

We will be adding more examples soon, but here are a couple to get you started. First, you'll need to set up your environment variables for OpenAI and Google SERP (OPENAI_ACCESS_TOKEN, SERPAPI_API_KEY). If you prefer not to set these variables in your environment, you can pass them directly into the API.

In the examples below, we added one rubygem to load the environment at the first line, but depending on what you want, you might not need this.
```ruby
require "dotenv/load"
require "boxcars"
```

Note: if you want to try out the examples below, run this command and then paste in the code segments of interest:
```bash
irb -r dotenv/load -r boxcars
```

### Direct Boxcar Use

```ruby
# run the calculator
engine = Boxcars::Openai.new(max_tokens: 256)
calc = Boxcars::Calculator.new(engine: engine)
puts calc.run "what is pi to the forth power divided by 22.1?"
```
Produces:
```text
> Entering Calculator#run
what is pi to the forth power divided by 22.1?
RubyREPL: puts(Math::PI**4 / 22.1)
Answer: 4.407651178009159

4.407651178009159
< Exiting Calculator#run
4.407651178009159
```

Note that since Openai is currently the most used Engine, if you do not pass in an engine, it will default as expected. So, this is the equialent shorter version of the above script:
```ruby
# run the calculator
calc = Boxcars::Calculator.new # just use the default Engine
puts calc.run "what is pi to the forth power divided by 22.1?"
```
You can change the default_engine with `Boxcars::configuration.default_engine = NewDefaultEngine`
### Boxcars currently implemmented

Here is what we have so far, but please put up a PR with your new ideas.
- GoogleSearch: uses the SERP API to do seaches
- Calculator: uses an Engine to generate ruby code to do math
- SQL: given an ActiveRecord connection, it will generate and run sql statments from a prompt.
- ActiveRecord: given an ActiveRecord connection, it will generate and run ActiveRecord statements from a prompt.

### Run a list of Boxcars
```ruby
# run a Train for a calculator, and search using default Engine
boxcars = [Boxcars::Calculator.new, Boxcars::Serp.new]
train = Boxcars.train.new(boxcars: boxcars)
puts train.run "What is pi times the square root of the average temperature in Austin TX in January?"
```
Produces:
```text
> Entering Zero Shot#run
What is pi times the square root of the average temperature in Austin TX in January?
Question: Average temperature in Austin TX in January
Answer: increase from 62°F to 64°F
#Observation: increase from 62°F to 64°F
> Entering Calculator#run
64°F x pi
RubyREPL: puts (64 * Math::PI).round(2)
Answer: 201.06

201.06
< Exiting Calculator#run
#Observation: 201.06
I now know the final answer
Final Answer: 201.06
< Exiting Zero Shot#run
201.06
```
### More Examples
See [this](https://github.com/BoxcarsAI/boxcars/blob/main/notebooks/boxcars_examples.ipynb) Jupyter Notebook for more examples.

Note, some folks that we talked to didn't know that you could run Ruby Jupyter notebooks. [You can](https://github.com/SciRuby/iruby).

### Logging
If you use this in a Rails application, or configure `Boxcars.configuration.logger = your_logger`, logging will go to your log file.

Also, if you set this flag: `Boxcars.configuration.lop_prompts = true`
The actual prompts handed to the connected Engine will be logged. This is off by default because it is very wordy, but handy if you are debugging prompts.

Otherwise, we print to standard out.
## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/BoxcarsAI/boxcars. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/BoxcarsAI/boxcars/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Boxcars project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/BoxcarsAI/boxcars/blob/main/CODE_OF_CONDUCT.md).
