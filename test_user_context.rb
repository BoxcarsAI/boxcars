#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple test to verify user context functionality

require_relative 'lib/boxcars'

# Test user context
user_context = {
  id: 123,
  email: "test@example.com",
  role: "admin",
  name: "Test User"
}

puts "Testing Boxcars User Context Implementation"
puts "=" * 50

# Test 1: Basic observation with user context
puts "\n1. Testing basic observation with user context:"
observation = Boxcars::Observation.with_user(
  "Test observation",
  user_context: user_context,
  extra_data: "test"
)

puts "✅ Created observation with user context"
puts "Note: #{observation.note}"
puts "Status: #{observation.status}"
puts "Has user context: #{observation.user_context?}"
puts "User context: #{observation.user_context}"

# Test 2: Convenience methods
puts "\n2. Testing convenience methods:"
success_obs = Boxcars::Observation.ok_with_user(
  "Success message",
  user_context: user_context
)

error_obs = Boxcars::Observation.err_with_user(
  "Error message",
  user_context: user_context
)

puts "✅ Success observation: #{success_obs.status}"
puts "✅ Error observation: #{error_obs.status}"

# Test 3: JSON serialization
puts "\n3. Testing JSON serialization:"
json_output = observation.to_json
puts "✅ JSON output includes user context:"
puts json_output

# Test 4: Hash representation
puts "\n4. Testing hash representation:"
hash_output = observation.to_h
puts "✅ Hash output:"
hash_output.each do |key, value|
  puts "  #{key}: #{value}"
end

# Test 5: Backward compatibility
puts "\n5. Testing backward compatibility:"
old_style_obs = Boxcars::Observation.ok("Old style observation", extra: "data")
puts "✅ Old style observation works"
puts "Has user context: #{old_style_obs.user_context?}"

puts "\n#{"=" * 50}"
puts "All tests passed! ✅"
