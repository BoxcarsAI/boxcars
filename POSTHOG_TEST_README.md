# Boxcars Engines PostHog Observability Test

This test program demonstrates how to use the Boxcars library with PostHog observability backend to track AI engine usage.

## Prerequisites

1. **PostHog Ruby Gem**: Install the required gem
   ```bash
   gem install posthog-ruby
   ```

2. **Environment Variables**: Ensure your `.env` file contains:
   ```
   POSTHOG_API_KEY=your_posthog_project_api_key
   POSTHOG_HOST=https://app.posthog.com  # or your self-hosted instance
   ```

3. **AI Provider API Keys**: For testing different engines, you'll need:
   ```
   openai_access_token=your_openai_token
   GOOGLE_API_KEY=your_google_api_key
   ANTHROPIC_API_KEY=your_anthropic_key
   GROQ_API_KEY=your_groq_key
   ```

## Usage

### Method 1: IRB Interactive Session (Recommended)

Start IRB with the required dependencies:

```bash
irb -r dotenv/load -r boxcars -r debug -r boxcars/observability_backends/posthog_backend
```

Then in the IRB session:

```ruby
# Load and run the test
load 'test_engines_with_posthog.rb'

# Or set up PostHog backend manually:
Boxcars::Observability.backend = Boxcars::PosthogBackend.new(
  api_key: ENV['POSTHOG_API_KEY'],
  host: ENV['POSTHOG_HOST']
)

# Run manual tests
manual_test(model: 'gpt-4o', prompt: 'What is machine learning?')
manual_test(model: 'flash', prompt: 'Explain Ruby in one sentence')
manual_test(model: 'sonnet', prompt: 'Write a short poem about coding')
```

### Method 2: Direct Ruby Execution

```bash
ruby test_engines_with_posthog.rb
```

## What the Test Does

1. **Initializes PostHog Backend**: Sets up the PostHog observability backend with your API credentials
2. **Tests Multiple Engines**: Runs tests against various AI engines:
   - Gemini Flash (Default)
   - GPT-4o (OpenAI)
   - Claude Sonnet (Anthropic)
   - Groq Llama
3. **Tracks Observability Events**: Each API call generates PostHog events with AI-specific properties
4. **Provides Manual Testing**: Includes a `manual_test` function for interactive testing

## PostHog Events

The test will generate events in PostHog with properties like:

- `$ai_model`: The AI model used (e.g., "gpt-4o", "gemini-2.5-flash")
- `$ai_provider`: The provider (e.g., "openai", "google", "anthropic")
- `$ai_input_tokens`: Number of input tokens
- `$ai_output_tokens`: Number of output tokens
- `$ai_latency`: Response time in seconds
- `$ai_http_status`: HTTP status code
- `$ai_trace_id`: Unique trace identifier
- `$ai_is_error`: Boolean indicating if there was an error

## Viewing Results

After running the test:

1. Go to your PostHog dashboard
2. Navigate to Events or Live Events
3. Look for events with AI-related properties
4. You can create insights and dashboards to analyze AI usage patterns

## Troubleshooting

- **Missing PostHog gem**: Install with `gem install posthog-ruby`
- **Missing API keys**: Check your `.env` file has the required keys
- **Engine errors**: Some engines may fail if you don't have valid API keys for those providers
- **No events in PostHog**: Check your PostHog API key and host configuration

## Available Models

You can test with these model aliases:

- `flash` - Gemini 2.5 Flash
- `gpt-4o` - OpenAI GPT-4o
- `sonnet` - Claude Sonnet
- `groq` - Groq Llama
- `online` - Perplexity Sonar
- And many more (see `lib/boxcars/engines.rb`)

## Example Manual Tests

```ruby
# Test different models
manual_test(model: 'flash', prompt: 'Explain quantum computing')
manual_test(model: 'gpt-4o', prompt: 'Write a Python function to sort a list')
manual_test(model: 'sonnet', prompt: 'What are the benefits of functional programming?')
manual_test(model: 'groq', prompt: 'Describe the difference between AI and ML')
