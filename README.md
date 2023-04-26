<h2 align="center">Boxcars</h2>

<h4 align="center">
  <a href="https://www.boxcars.ai">Website</a> |
  <a href="https://www.boxcars.ai/blog">Blog</a> |
  <a href="https://github.com/BoxcarsAI/boxcars/wiki">Documentation</a> 
</h4>

<p align="center">
  <a href="https://github.com/BoxcarsAI/boxcars/blob/main/LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-informational" alt="License"></a>
</p>

Boxcars is a gem that enables you to create new systems with AI composability, using various concepts such as OpenAI, Search, SQL, Rails Active Record and more. This can even be extended with your concepts as well (including your concepts).

This gem was inspired by the popular Python library Langchain. However, we wanted to give it a Ruby spin and make it more user-friendly for beginners to get started.

## Concepts
All of these concepts are in a module named Boxcars:

- Boxcar - an encapsulation that performs something of interest (such as search, math, SQL, an Active Record Query, or an API call to a service). A Boxcar can use an Engine (described below) to do its work, and if not specified but needed, the default Engine is used `Boxcars.engine`.
- Train - Given a list of Boxcars and optionally an Engine, a Train breaks down a problem into pieces for individual Boxcars to solve. The individual results are then combined until a final answer is found. ZeroShot is the only current implementation of Train (but we are adding more soon), and you can either construct it directly or use `Boxcars::train` when you want to build a Train.
- Prompt - used by an Engine to generate text results. Our Boxcars have built-in prompts, but you have the flexibility to change or augment them if you so desire.
- Engine - an entity that generates text from a Prompt. OpenAI's LLM text generator is the default Engine if no other is specified, and you can override the default engine if so desired (`Boxcar.configuration.default_engine`).

## Security
Currently, our system is designed for individuals who already possess administrative privileges for their project. It is likely possible to manipulate the system's prompts to carry out malicious actions, but if you already have administrative access, you can perform such actions without requiring boxcars in the first place.

*Note:* We are actively seeking ways to improve our system's ability to identify and prevent any nefarious attempts from occurring. If you have any suggestions or recommendations, please feel free to share them with us by either finding an existing issue or creating a new one and providing us with your feedback.

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
RubyREPL: puts (Math::PI**4)/22.1
Answer: 4.407651178009159

{"status":"ok","answer":"4.407651178009159","explanation":"Answer: 4.407651178009159","code":"puts (Math::PI**4)/22.1"}
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
### Boxcars currently implemented

Here is what we have so far, but please put up a PR with your new ideas.
- GoogleSearch: uses the SERP API to do seaches
- WikipediaSearch: uses the Wikipedia API to do searches
- Calculator: uses an Engine to generate ruby code to do math
- SQL: given an ActiveRecord connection, it will generate and run sql statments from a prompt.
- ActiveRecord: given an ActiveRecord connection, it will generate and run ActiveRecord statements from a prompt.
- Swagger: give a Swagger Open API file (YAML or JSON), answer questions about or run against the referenced service. See [here](https://github.com/BoxcarsAI/boxcars/blob/main/notebooks/swagger_examples.ipynb) for examples.

### Run a list of Boxcars
```ruby
# run a Train for a calculator, and search using default Engine
boxcars = [Boxcars::Calculator.new, Boxcars::GoogleSearch.new]
train = Boxcars.train.new(boxcars: boxcars)
train.run "What is pi times the square root of the average temperature in Austin TX in January?"
```
Produces:
```text
> Entering Zero Shot#run
What is pi times the square root of the average temperature in Austin TX in January?
Thought: We need to find the average temperature in Austin TX in January and then multiply it by pi and the square root of the average temperature. We can use a search engine to find the average temperature in Austin TX in January and a calculator to perform the multiplication. 
Question: Average temperature in Austin TX in January
Answer: January Weather in Austin Texas, United States. Daily high temperatures increase by 2°F, from 62°F to 64°F, rarely falling below 45°F or exceeding 76° ...
Observation: January Weather in Austin Texas, United States. Daily high temperatures increase by 2°F, from 62°F to 64°F, rarely falling below 45°F or exceeding 76° ...
Thought: We have found the average temperature in Austin TX in January, which is 64°F. Now we can use a calculator to perform the multiplication.
> Entering Calculator#run
pi * sqrt(64)
RubyREPL: puts(Math::PI * Math.sqrt(64))
Answer: 25.132741228718345

{"status":"ok","answer":"25.132741228718345","explanation":"Answer: 25.132741228718345","code":"puts(Math::PI * Math.sqrt(64))"}
< Exiting Calculator#run
Observation: 25.132741228718345
We have the final answer.

Final Answer: 25.132741228718345

Next Actions:
1. What is the average temperature in Austin TX in July?
2. What is the value of pi to 10 decimal places?
3. What is the square root of the average temperature in Miami FL in January?
< Exiting Zero Shot#run
```
### More Examples
See [this](https://github.com/BoxcarsAI/boxcars/blob/main/notebooks/boxcars_examples.ipynb) Jupyter Notebook for more examples.

For the new Swagger boxcar, see [this](https://github.com/BoxcarsAI/boxcars/blob/main/notebooks/swagger_examples.ipynb) Jupyter Notebook.

Note, some folks that we talked to didn't know that you could run Ruby Jupyter notebooks. [You can](https://github.com/SciRuby/iruby).

### Logging
If you use this in a Rails application, or configure `Boxcars.configuration.logger = your_logger`, logging will go to your log file.

Also, if you set this flag: `Boxcars.configuration.log_prompts = true`
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
