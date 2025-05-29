#!/usr/bin/env ruby

# Force reload of the observability module
$LOADED_FEATURES.reject! { |f| f.include?('openai_observability') }

require './lib/boxcars'
require 'json'

# Mock PostHog backend to capture events
class TestPosthogBackend
  include Boxcars::ObservabilityBackend

  attr_reader :captured_events

  def initialize
    @captured_events = []
  end

  def track(event:, properties:)
    @captured_events << { event: event, properties: properties }
    puts "\n=== CAPTURED EVENT ==="
    puts "Event: #{event}"
    puts "Properties with PostHog prefixes:"
    properties.each do |key, value|
      if key.to_s.start_with?('$ai_')
        puts "  #{key}: #{value.is_a?(String) && value.length > 100 ? "#{value[0..100]}..." : value}"
      end
    end
    puts "All properties count: #{properties.keys.length}"
    puts "=====================\n"
  end
end

# Set up test backend
test_backend = TestPosthogBackend.new
Boxcars::Observability.backend = test_backend

# Test the observability tracking
puts "Testing OpenAI Observability with PostHog properties..."

# Create an instance of the OpenAI observability module for testing
test_class = Class.new do
  include Boxcars::OpenAIObservability

  def test_tracking
    call_context = {
      start_time: Time.now - 1.5, # 1.5 seconds ago
      prompt_object: Boxcars::Prompt.new(template: "Say hello"),
      inputs: {},
      api_request_params: { model: "gpt-4o-mini", messages: [{ role: "user", content: "Say hello" }] },
      current_params: { model: "gpt-4o-mini", temperature: 0.7 },
      is_chat_model: true
    }

    response_data = {
      success: true,
      response_obj: {
        "choices" => [
          {
            "message" => {
              "content" => "Hello! This is a test response from the AI."
            }
          }
        ],
        "usage" => {
          "prompt_tokens" => 15,
          "completion_tokens" => 12,
          "total_tokens" => 27
        },
        "model" => "gpt-4o-mini"
      },
      status_code: 200,
      error: nil
    }

    puts "About to call _track_openai_observability..."
    _track_openai_observability(call_context, response_data)
    puts "Finished calling _track_openai_observability"
  end
end

# Run the test
test_instance = test_class.new
test_instance.test_tracking

# Check what was captured
puts "\n=== ANALYSIS ==="
if test_backend.captured_events.empty?
  puts "❌ No events were captured!"
else
  event = test_backend.captured_events.first
  puts "✅ Event captured: #{event[:event]}"

  # Check for PostHog required properties
  required_props = [
    '$ai_trace_id', '$ai_model', '$ai_provider', '$ai_input',
    '$ai_input_tokens', '$ai_output_choices', '$ai_output_tokens',
    '$ai_latency', '$ai_http_status', '$ai_base_url', '$ai_is_error'
  ]

  missing_props = []
  present_props = []

  required_props.each do |prop|
    if event[:properties].key?(prop.to_sym)
      present_props << prop
    else
      missing_props << prop
    end
  end

  puts "\n✅ Present PostHog properties (#{present_props.length}/#{required_props.length}):"
  present_props.each { |prop| puts "  - #{prop}" }

  if missing_props.any?
    puts "\n❌ Missing PostHog properties:"
    missing_props.each { |prop| puts "  - #{prop}" }
  else
    puts "\n🎉 All required PostHog properties are present!"
  end

  # Check specific values
  props = event[:properties]
  puts "\n=== PROPERTY VALUES ==="
  puts "$ai_event: #{event[:event]}"
  puts "$ai_provider: #{props[:$ai_provider]}"
  puts "$ai_model: #{props[:$ai_model]}"
  puts "$ai_input_tokens: #{props[:$ai_input_tokens]}"
  puts "$ai_output_tokens: #{props[:$ai_output_tokens]}"
  puts "$ai_latency: #{props[:$ai_latency]} seconds"
  puts "$ai_http_status: #{props[:$ai_http_status]}"
  puts "$ai_is_error: #{props[:$ai_is_error]}"

  # Show all property keys for debugging
  puts "\n=== ALL PROPERTY KEYS ==="
  props.keys.sort.each { |key| puts "  - #{key}" }
end
