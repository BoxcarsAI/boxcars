#!/usr/bin/env ruby

# Test program for Boxcars Engines with PostHog observability backend
#
# Usage:
# irb -r dotenv/load -r boxcars -r debug -r boxcars/observability_backends/posthog_backend
# 3.4.4 :001 > load 'test_engines_with_posthog.rb'

require 'dotenv/load'
require 'boxcars'
require 'boxcars/observability_backends/posthog_backend'
require 'debug'

puts "🚀 Starting Boxcars Engines Test with PostHog Backend"
puts "=" * 60

# Check if environment variables are available
posthog_api_key = ENV.fetch('POSTHOG_API_KEY', nil)
posthog_host = ENV.fetch('POSTHOG_HOST', 'https://app.posthog.com')

if posthog_api_key.nil? || posthog_api_key.empty?
  puts "❌ ERROR: POSTHOG_API_KEY environment variable is not set!"
  puts "Please ensure your .env file contains POSTHOG_API_KEY"
  exit 1
end

puts "✅ PostHog API Key found: #{posthog_api_key[0..8]}..."
puts "✅ PostHog Host: #{posthog_host}"

# Initialize PostHog backend
begin
  puts "\n📡 Initializing PostHog backend..."

  posthog_backend = Boxcars::PosthogBackend.new(
    api_key: posthog_api_key,
    host: posthog_host,
    on_error: proc do |status, body|
      puts "❌ PostHog Error: Status #{status}, Body: #{body}"
    end
  )

  # Set the observability backend
  Boxcars::Observability.backend = posthog_backend
  puts "✅ PostHog backend initialized and set as observability backend"
rescue LoadError => e
  puts "❌ ERROR: #{e.message}"
  puts "Please install the posthog-ruby gem: gem install posthog-ruby"
  exit 1
rescue => e
  puts "❌ ERROR initializing PostHog backend: #{e.message}"
  exit 1
end

# Define test engines to try
test_engines = [
  # { name: "Perplexity AI", model: "sonar" },
  # { name: "Qwen", model: "qwen" },
  # { name: "Mistral", model: "mistral" },
  { name: "Gemini Flash (Default)", model: "flash" },
  # { name: "GPT-4o", model: "gpt-4o" },
  # { name: "Claude Sonnet", model: "sonnet" },
  # { name: "Groq Llama", model: "groq" }
]

# Test prompts
test_prompts = [
  "What is 2 + 2?",
  "Explain quantum computing in one sentence.",
  "Write a haiku about programming."
]

puts "\n🧪 Testing Engines with PostHog Observability"
puts "=" * 60

successful_tests = 0
total_tests = 0

test_engines.each do |engine_config|
  puts "\n🔧 Testing #{engine_config[:name]} (#{engine_config[:model]})"
  puts "-" * 40

  begin
    # Create engine instance
    engine = Boxcars::Engines.engine(model: engine_config[:model])
    puts "✅ Engine created successfully"

    # Test with a simple prompt
    test_prompt = test_prompts.sample
    puts "📝 Testing with prompt: '#{test_prompt}'"

    total_tests += 1
    start_time = Time.now

    # Make the API call - this should trigger observability tracking
    result = engine.run(test_prompt)

    end_time = Time.now
    duration = end_time - start_time

    if result
      puts "✅ API call successful (#{duration.round(2)}s)"
      puts "📄 Response preview: #{result[0..100]}#{'...' if result.length > 100}"
      successful_tests += 1
    else
      puts "⚠️  API call returned unexpected result type: #{result.class}"
    end
  rescue => e
    puts "❌ Error testing #{engine_config[:name]}: #{e.message}"
    puts "   #{e.class}: #{e.backtrace.join("\n   ")}" # Always show full backtrace
  end

  # Small delay between tests
  sleep(1)
end

# Flush events to ensure they're sent (important for PostHog and testing)
puts "\n=== FLUSHING EVENTS ==="
Boxcars::Observability.flush

puts "\n📊 Test Summary"
puts "=" * 60
puts "Total tests: #{total_tests}"
puts "Successful: #{successful_tests}"
puts "Failed: #{total_tests - successful_tests}"
puts "Success rate: #{total_tests.positive? ? (successful_tests.to_f / total_tests * 100).round(1) : 0}%"

if successful_tests.positive?
  puts "\n🎉 PostHog observability events should now be visible in your PostHog dashboard!"
  puts "   Look for events with AI-related properties like:"
  puts "   - $ai_model, $ai_provider, $ai_input_tokens, $ai_output_tokens"
  puts "   - $ai_latency, $ai_http_status, $ai_trace_id"
end

puts "\n✨ Test completed!"

# Optional: Manual test function for interactive use
def manual_test(model: "flash", prompt: "Hello, how are you?")
  puts "\n🔧 Manual Test: #{model}"
  puts "📝 Prompt: #{prompt}"

  begin
    engine = Boxcars::Engines.engine(model: model)
    start_time = Time.now
    result = engine.run(prompt)
    duration = Time.now - start_time

    puts "✅ Success (#{duration.round(2)}s)"
    puts "📄 Response: #{result.completion}"
    result
  rescue => e
    puts "❌ Error: #{e.message}"
    nil
  end
end

puts "\n💡 You can run manual tests with:"
puts "   manual_test(model: 'gpt-4o', prompt: 'Your question here')"
puts "   Available models: flash, gpt-4o, sonnet, groq, online, etc."
