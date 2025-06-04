<h2 align="center">Boxcars</h2>

<h4 align="center">
  <a href="https://www.boxcars.ai">Website</a> |
  <a href="https://www.boxcars.ai/blog">Blog</a> |
  <a href="https://github.com/BoxcarsAI/boxcars/wiki">Documentation</a>
</h4>

<p align="center">
  <a href="https://github.com/BoxcarsAI/boxcars/blob/main/LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-informational" alt="License"></a>
</p>

Boxcars is a gem that enables you to create new systems with AI composability, using various concepts such as LLMs (OpenAI, Anthropic, Gpt4all), Search, SQL (with both Sequel and Active Record support), Rails Active Record, Vector Search and more. This can even be extended with your concepts as well (including your concepts).

This gem was inspired by the popular Python library Langchain. However, we wanted to give it a Ruby spin and make it more user-friendly for beginners to get started.

## Concepts
All of these concepts are in a module named Boxcars:

- Boxcar - an encapsulation that performs something of interest (such as search, math, SQL, an Active Record Query, or an API call to a service). A Boxcar can use an Engine (described below) to do its work, and if not specified but needed, the default Engine is used `Boxcars.engine`.
- Train - Given a list of Boxcars and optionally an Engine, a Train breaks down a problem into pieces for individual Boxcars to solve. The individual results are then combined until a final answer is found. ZeroShot is the only current implementation of Train (but we are adding more soon), and you can either construct it directly or use `Boxcars::train` when you want to build a Train.
- Prompt - used by an Engine to generate text results. Our Boxcars have built-in prompts, but you have the flexibility to change or augment them if you so desire.
- Engine - an entity that generates text from a Prompt. OpenAI's LLM text generator is the default Engine if no other is specified, and you can override the default engine if so desired (`Boxcar.configuration.default_engine`). We have an Engine for Anthropic's Claude API named `Boxcars::Anthropic`, and another Engine for GPT named `Boxcars::Gpt4allEng`.
- VectorStore - a place to store and query vectors.

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

We will be adding more examples soon, but here are a couple to get you started. First, you'll need to set up your environment variables for services like OpenAI, Anthropic, and Google SERP (OPENAI_ACCESS_TOKEN, ANTHROPIC_API_KEY,SERPAPI_API_KEY) etc. If you prefer not to set these variables in your environment, you can pass them directly into the API.

In the examples below, we added one Ruby gem to load the environment at the first line, but depending on what you want, you might not need this.
```ruby
require "dotenv/load"
require "boxcars"
```

Note: if you want to try out the examples below, run this command and then paste in the code segments of interest:
```bash
irb -r dotenv/load -r boxcars

# or if you prefer local repository
irb -r dotenv/load -r ./lib/boxcars
```

### Direct Boxcar Use

```ruby
# run the calculator
engine = Boxcars::Openai.new(max_tokens: 256)
calc = Boxcars::Calculator.new(engine: engine)
puts calc.run "what is pi to the fourth power divided by 22.1?"
```
Produces:
```text
> Entering Calculator#run
what is pi to the fourth power divided by 22.1?
RubyREPL: puts (Math::PI**4)/22.1
Answer: 4.407651178009159

{"status":"ok","answer":"4.407651178009159","explanation":"Answer: 4.407651178009159","code":"puts (Math::PI**4)/22.1"}
< Exiting Calculator#run
4.407651178009159
```

Note that since Openai is currently the most used Engine, if you do not pass in an engine, it will default as expected. So, this is the equivalent shorter version of the above script:
```ruby
# run the calculator
calc = Boxcars::Calculator.new # just use the default Engine
puts calc.run "what is pi to the fourth power divided by 22.1?"
```
You can change the default_engine with `Boxcars::configuration.default_engine = NewDefaultEngine`
### Boxcars currently implemented

Here is what we have so far, but please put up a PR with your new ideas.
- GoogleSearch: uses the SERP API to do searches
- WikipediaSearch: uses the Wikipedia API to do searches
- Calculator: uses an Engine to generate ruby code to do math
- SQL: given an ActiveRecord connection, it will generate and run sql statements from a prompt.
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

For the Swagger boxcar, see [this](https://github.com/BoxcarsAI/boxcars/blob/main/notebooks/swagger_examples.ipynb) Jupyter Notebook.

For simple vector storage and search, see [this](https://github.com/BoxcarsAI/boxcars/blob/main/notebooks/vector_search_examples.ipynb) Jupyter Notebook.

Note, some folks that we talked to didn't know that you could run Ruby Jupyter notebooks. [You can](https://github.com/SciRuby/iruby).

### Logging
If you use this in a Rails application, or configure `Boxcars.configuration.logger = your_logger`, logging will go to your log file.

Also, if you set this flag: `Boxcars.configuration.log_prompts = true`
The actual prompts handed to the connected Engine will be logged. This is off by default because it is very wordy, but handy if you are debugging prompts.

Otherwise, we print to standard out.

### Engine Factory (Engines)

Boxcars provides a convenient factory class `Boxcars::Engines` that simplifies creating engine instances using model names and aliases instead of remembering full class names and model strings.

#### Basic Usage

```ruby
# Using default model (gemini-2.5-flash-preview-05-20)
engine = Boxcars::Engines.engine

# Using specific models with convenient aliases
gpt_engine = Boxcars::Engines.engine(model: "gpt-4o")
claude_engine = Boxcars::Engines.engine(model: "sonnet")
gemini_engine = Boxcars::Engines.engine(model: "flash")
groq_engine = Boxcars::Engines.engine(model: "groq")
```

#### Supported Model Aliases

**OpenAI Models:**
- `"gpt-4o"`, `"gpt-3.5-turbo"`, `"o1-preview"` - Creates `Boxcars::Openai` engines

**Anthropic Models:**
- `"anthropic"`, `"sonnet"` - Creates `Boxcars::Anthropic` with Claude Sonnet
- `"opus"` - Creates `Boxcars::Anthropic` with Claude Opus
- `"claude-3-5-sonnet"`, etc. - Any model starting with "claude-"

**Groq Models:**
- `"groq"` - Creates `Boxcars::Groq` with Llama 3.3 70B
- `"deepseek"` - Creates `Boxcars::Groq` with DeepSeek R1
- `"mistral"` - Creates `Boxcars::Groq` with Mistral
- Models starting with `"mistral-"`, `"meta-llama/"`, or `"deepseek-"`

**Gemini Models:**
- `"flash"`, `"gemini-flash"` - Creates `Boxcars::GeminiAi` with Gemini 2.5 Flash
- `"gemini-pro"` - Creates `Boxcars::GeminiAi` with Gemini 2.5 Pro
- Any model starting with `"gemini-"`

**Perplexity Models:**
- `"online"`, `"sonar"` - Creates `Boxcars::Perplexityai` with Sonar
- `"sonar-pro"`, `"huge"` - Creates `Boxcars::Perplexityai` with Sonar Pro
- Models containing `"-sonar-"`

**Together AI Models:**
- `"together-model-name"` - Creates `Boxcars::Together` (strips "together-" prefix)

#### JSON-Optimized Engines

For applications requiring JSON responses, use the `json_engine` method:

```ruby
# Creates engine optimized for JSON output
json_engine = Boxcars::Engines.json_engine(model: "gpt-4o")

# Automatically removes response_format for models that don't support it
json_claude = Boxcars::Engines.json_engine(model: "sonnet")
```

#### Passing Additional Parameters

```ruby
# Pass any additional parameters to the underlying engine
engine = Boxcars::Engines.engine(
  model: "gpt-4o",
  temperature: 0.7,
  max_tokens: 1000,
  top_p: 0.9
)
```

#### Using with Boxcars

```ruby
# Use the factory with any Boxcar
engine = Boxcars::Engines.engine(model: "sonnet")
calc = Boxcars::Calculator.new(engine: engine)
result = calc.run "What is 15 * 23?"

# Or in a Train
boxcars = [
  Boxcars::Calculator.new(engine: Boxcars::Engines.engine(model: "gpt-4o")),
  Boxcars::GoogleSearch.new(engine: Boxcars::Engines.engine(model: "flash"))
]
train = Boxcars.train.new(boxcars: boxcars)
```

### Overriding the Default Engine Model

Boxcars provides several ways to override the default engine model used throughout your application. The default model is currently `"gemini-2.5-flash-preview-05-20"`, but you can customize this behavior.

#### Global Configuration

Set a global default model that will be used by `Boxcars::Engines.engine()` when no model is specified:

```ruby
# Set the default model globally
Boxcars.configuration.default_model = "gpt-4o"

# Now all engines created without specifying a model will use GPT-4o
engine = Boxcars::Engines.engine  # Uses gpt-4o
calc = Boxcars::Calculator.new    # Uses gpt-4o via default engine
```

#### Configuration Block

Use a configuration block for more organized setup:

```ruby
Boxcars.configure do |config|
  config.default_model = "sonnet"  # Use Claude Sonnet as default
  config.logger = Rails.logger     # Set custom logger
  config.log_prompts = true        # Enable prompt logging
end
```

#### Per-Instance Override

Override the model for specific engine instances:

```ruby
# Global default is gemini-flash, but use different models per boxcar
default_engine = Boxcars::Engines.engine                    # Uses global default
gpt_engine = Boxcars::Engines.engine(model: "gpt-4o")       # Uses GPT-4o
claude_engine = Boxcars::Engines.engine(model: "sonnet")    # Uses Claude Sonnet

# Use different engines for different boxcars
calc = Boxcars::Calculator.new(engine: gpt_engine)
search = Boxcars::GoogleSearch.new(engine: claude_engine)
```

#### Environment-Based Configuration

Set the default model via environment variables or initialization:

```ruby
# In your application initialization (e.g., Rails initializer)
if Rails.env.production?
  Boxcars.configuration.default_model = "gpt-4o"      # Use GPT-4o in production
elsif Rails.env.development?
  Boxcars.configuration.default_model = "flash"       # Use faster Gemini Flash in development
else
  Boxcars.configuration.default_model = "groq"        # Use Groq for testing
end
```

#### Model Resolution Priority

The `Boxcars::Engines.engine()` method resolves the model in this order:

1. **Explicit model parameter**: `Boxcars::Engines.engine(model: "gpt-4o")`
2. **Global configuration**: `Boxcars.configuration.default_model`
3. **Built-in default**: `"gemini-2.5-flash-preview-05-20"`

#### Supported Model Aliases

When setting `default_model`, you can use any of the supported model aliases:

```ruby
# These are all valid default_model values:
Boxcars.configuration.default_model = "gpt-4o"        # OpenAI GPT-4o
Boxcars.configuration.default_model = "sonnet"        # Claude Sonnet
Boxcars.configuration.default_model = "flash"         # Gemini Flash
Boxcars.configuration.default_model = "groq"          # Groq Llama
Boxcars.configuration.default_model = "online"        # Perplexity Sonar
```

#### Legacy Engine Configuration

You can also override the default engine class (though this is less common):

```ruby
# Override the default engine class entirely
Boxcars.configuration.default_engine = Boxcars::Anthropic

# Now Boxcars.engine returns Anthropic instead of OpenAI
default_engine = Boxcars.engine  # Returns Boxcars::Anthropic instance
```

**Note**: When using `default_engine`, the `default_model` setting is ignored since you're specifying the engine class directly.

### Observability

Boxcars includes a comprehensive observability system that allows you to track and monitor AI operations across your application. The system provides insights into LLM calls, performance metrics, errors, and usage patterns.

#### Core Components

**Observability Class**: The central tracking interface that provides a simple `track` method for recording events.

**ObservabilityBackend Module**: An interface that defines how tracking backends should be implemented. All backends must include this module and implement a `track` method.

**Built-in Backends**:
- **PosthogBackend**: Sends events to PostHog for analytics and user behavior tracking
- **MultiBackend**: Allows sending events to multiple backends simultaneously

#### Configuration

Set up observability by configuring a backend:

```ruby
# Using PostHog backend
require 'boxcars/observability_backends/posthog_backend'
require 'posthog'

# Create a PostHog client with your desired configuration
posthog_client = PostHog::Client.new(
  api_key: ENV['POSTHOG_API_KEY'] || 'your_posthog_api_key',
  host: 'https://app.posthog.com', # or your self-hosted instance
  on_error: proc { |status, body| 
    Rails.logger.warn "PostHog error: #{status} - #{body}" 
  }
)

Boxcars.configure do |config|
  config.observability_backend = Boxcars::PosthogBackend.new(client: posthog_client)
end

# Using multiple backends
require 'boxcars/observability_backends/multi_backend'

# Create PostHog client
posthog_client = PostHog::Client.new(
  api_key: ENV['POSTHOG_API_KEY'],
  host: 'https://app.posthog.com'
)
backend1 = Boxcars::PosthogBackend.new(client: posthog_client)
backend2 = YourCustomBackend.new

Boxcars.configure do |config|
  config.observability_backend = Boxcars::MultiBackend.new([backend1, backend2])
end
```

#### Automatic Tracking

Boxcars automatically tracks LLM calls with detailed metrics:

```ruby
# This automatically generates observability events
engine = Boxcars::Openai.new
calc = Boxcars::Calculator.new(engine: engine)
result = calc.run "what is 2 + 2?"
```

**Tracked Properties Include**:
- `provider`: The LLM provider (e.g., "openai", "anthropic")
- `model_name`: The specific model used
- `prompt_content`: The conversation messages sent to the LLM
- `inputs`: Any template inputs provided
- `duration_ms`: Request duration in milliseconds
- `success`: Whether the call succeeded
- `status_code`: HTTP response status
- `error_message`: Error details if the call failed
- `response_raw_body`: Raw API response
- `api_call_parameters`: Parameters sent to the API

#### Manual Tracking

You can also track custom events:

```ruby
Boxcars::Observability.track(
  event: 'custom_operation',
  properties: {
    user_id: 'user_123',
    operation_type: 'data_processing',
    duration_ms: 150,
    success: true
  }
)
```

#### Creating Custom Backends

Implement your own backend by including the `ObservabilityBackend` module:

```ruby
class CustomBackend
  include Boxcars::ObservabilityBackend
  
  def track(event:, properties:)
    # Your custom tracking logic here
    puts "Event: #{event}, Properties: #{properties}"
  end
end

Boxcars.configure do |config|
  config.observability_backend = CustomBackend.new
end
```

#### Error Handling

The observability system is designed to fail silently to prevent tracking issues from disrupting your main application flow. If a backend raises an error, it will be caught and ignored, ensuring your AI operations continue uninterrupted.

#### PostHog Integration

The PostHog backend requires the `posthog-ruby` gem:

```ruby
# Add to your Gemfile
gem 'posthog-ruby'

# Configure the backend
require 'posthog'

posthog_client = PostHog::Client.new(
  api_key: ENV['POSTHOG_API_KEY'],
  host: 'https://app.posthog.com',
  on_error: proc { |status, body| 
    Rails.logger.warn "PostHog error: #{status} - #{body}" 
  }
)

Boxcars.configure do |config|
  config.observability_backend = Boxcars::PosthogBackend.new(client: posthog_client)
end
```

Events are automatically associated with users when a `user_id` property is provided. Anonymous events use a default identifier.


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/BoxcarsAI/boxcars. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/BoxcarsAI/boxcars/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Boxcars project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/BoxcarsAI/boxcars/blob/main/CODE_OF_CONDUCT.md).
