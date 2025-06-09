# User Context in Boxcars Observations

This guide explains how to use the new user context feature in Boxcars observations to track which user performed specific actions.

## Overview

The user context feature allows you to associate user information with Boxcars observations, enabling better tracking, debugging, and analytics. This is particularly useful when using Boxcars in web applications where you want to tie AI operations to specific users.

## Key Features

- **Non-intrusive**: Uses the existing `added_context` mechanism
- **Backward compatible**: Existing code continues to work unchanged
- **Flexible**: You control what user data is included
- **Analytics-ready**: Automatically formats user data for analytics systems like PostHog
- **Privacy-conscious**: Only includes data you explicitly provide

## Enhanced Observation Class

### New Methods

#### `Observation.with_user(note, user_context:, status: :ok, **additional_context)`

Creates an observation with user context.

```ruby
user_context = {
  id: current_user.id,
  email: current_user.email,
  role: current_user.role
}

observation = Boxcars::Observation.with_user(
  "User performed search",
  user_context: user_context,
  query: "machine learning",
  results_count: 42
)
```

#### `Observation.ok_with_user(note, user_context:, **additional_context)`

Creates a successful observation with user context.

```ruby
observation = Boxcars::Observation.ok_with_user(
  "Search completed successfully",
  user_context: user_context,
  processing_time_ms: 150
)
```

#### `Observation.err_with_user(note, user_context:, **additional_context)`

Creates an error observation with user context.

```ruby
observation = Boxcars::Observation.err_with_user(
  "Search failed due to timeout",
  user_context: user_context,
  error_code: "TIMEOUT"
)
```

### New Instance Methods

#### `#user_context`

Returns the user context hash if present, `nil` otherwise.

```ruby
observation.user_context
# => {id: 123, email: "user@example.com", role: "admin"}
```

#### `#user_context?`

Returns `true` if the observation has user context, `false` otherwise.

```ruby
observation.user_context?
# => true
```

## Enhanced Observability System

### Updated Track Method

The `Boxcars::Observability.track` method now accepts an optional `observation` parameter:

```ruby
Boxcars::Observability.track(
  event: 'user_action',
  properties: { action_type: 'search' },
  observation: observation_with_user_context
)
```

When an observation with user context is provided, the user data is automatically merged into the tracking properties with `$user_` prefixes (PostHog compatible).

### New Track Observation Method

```ruby
Boxcars::Observability.track_observation(
  observation,
  event: 'custom_event_name',  # optional, defaults to 'boxcar_observation'
  additional_property: 'value'
)
```

This method automatically:
- Extracts observation details (note, status, timestamp)
- Includes all additional context from the observation
- Merges user context with `$user_` prefixes
- Sends everything to your configured observability backend

## Rails Integration Pattern

### Controller Helper Methods

Create helper methods in your `ApplicationController`:

```ruby
class ApplicationController < ActionController::Base
  private

  # Helper method to create observations with user context
  def create_observation_with_user(note, status: :ok, **additional_context)
    if current_user
      Boxcars::Observation.with_user(
        note,
        user_context: current_user.to_user_context,
        status: status,
        **additional_context
      )
    else
      Boxcars::Observation.new(note: note, status: status, **additional_context)
    end
  end

  # Helper method for successful operations
  def success_observation_with_user(note, **additional_context)
    create_observation_with_user(note, status: :ok, **additional_context)
  end

  # Helper method for error operations
  def error_observation_with_user(note, **additional_context)
    create_observation_with_user(note, status: :error, **additional_context)
  end
end
```

### User Model Extension

Add a method to your User model to convert user data to context:

```ruby
class User < ApplicationRecord
  def to_user_context
    {
      id: id,
      email: email,
      role: role,
      # Add other relevant fields, but be mindful of privacy
      # Don't include sensitive data like passwords, tokens, etc.
    }
  end
end
```

### Usage in Controllers

```ruby
class SearchController < ApplicationController
  def search
    query = params[:query]
    
    begin
      # Perform search with Boxcars
      results = perform_boxcar_search(query)
      
      # Track successful search
      observation = success_observation_with_user(
        "Search completed successfully",
        query: query,
        results_count: results.count,
        processing_time_ms: 250
      )
      
      Boxcars::Observability.track_observation(
        observation,
        event: 'search_completed',
        controller: 'SearchController',
        action: 'search'
      )
      
      render json: { results: results }
      
    rescue StandardError => e
      # Track search error
      error_observation = error_observation_with_user(
        "Search failed: #{e.message}",
        query: query,
        error_class: e.class.name
      )
      
      Boxcars::Observability.track_observation(
        error_observation,
        event: 'search_failed',
        controller: 'SearchController',
        action: 'search'
      )
      
      render json: { error: "Search failed" }, status: 500
    end
  end
end
```

## Analytics Integration

### PostHog Integration

When using PostHog as your observability backend, user context is automatically formatted with `$user_` prefixes:

```ruby
# This user context:
user_context = {
  id: 123,
  email: "user@example.com",
  role: "admin"
}

# Becomes these PostHog properties:
{
  "$user_id" => 123,
  "$user_email" => "user@example.com", 
  "$user_role" => "admin"
}
```

This allows PostHog to automatically associate events with users and enables user-based analytics and segmentation.

### Custom Analytics Systems

For other analytics systems, you can access the user context directly:

```ruby
observation = Boxcars::Observation.ok_with_user("Action completed", user_context: user_data)

# Access user context
user_info = observation.user_context
# => {id: 123, email: "user@example.com", role: "admin"}

# Include in your custom tracking
your_analytics.track(
  event: 'boxcar_action',
  user_id: user_info[:id],
  user_email: user_info[:email],
  properties: observation.to_h
)
```

## Privacy Considerations

### What to Include

**Safe to include:**
- User ID (for tracking purposes)
- Email (if needed for support)
- Role/permissions level
- Account type (free, premium, etc.)
- Tenant/organization ID

**Avoid including:**
- Passwords or password hashes
- API keys or tokens
- Personal identification numbers
- Credit card information
- Any other sensitive personal data

### Example Safe User Context

```ruby
def to_user_context
  {
    id: id,
    email: email,
    role: role,
    account_type: subscription&.plan_name,
    organization_id: organization_id,
    created_at: created_at.iso8601,
    last_login: last_sign_in_at&.iso8601
  }
end
```

## Testing

### RSpec Examples

```ruby
RSpec.describe "User Context in Observations" do
  let(:user_context) do
    {
      id: 123,
      email: "test@example.com",
      role: "admin"
    }
  end

  it "creates observation with user context" do
    observation = Boxcars::Observation.ok_with_user(
      "Test action",
      user_context: user_context
    )

    expect(observation.user_context?).to be true
    expect(observation.user_context[:id]).to eq(123)
    expect(observation.user_context[:email]).to eq("test@example.com")
  end

  it "tracks observation with user context" do
    observation = Boxcars::Observation.ok_with_user(
      "Test action",
      user_context: user_context
    )

    expect(Boxcars::Observability).to receive(:track).with(
      event: 'test_event',
      properties: hash_including(
        "$user_id" => 123,
        "$user_email" => "test@example.com"
      )
    )

    Boxcars::Observability.track(
      event: 'test_event',
      properties: {},
      observation: observation
    )
  end
end
```

## Migration Guide

### Existing Code

Your existing observation code continues to work unchanged:

```ruby
# This still works exactly as before
observation = Boxcars::Observation.ok("Action completed", extra: "data")
Boxcars::Observability.track(event: 'action', properties: { type: 'test' })
```

### Adding User Context

To add user context to existing observations, simply replace:

```ruby
# Before
observation = Boxcars::Observation.ok("Action completed")

# After  
observation = Boxcars::Observation.ok_with_user(
  "Action completed",
  user_context: current_user.to_user_context
)
```

### Updating Tracking Calls

To include user context in tracking:

```ruby
# Before
Boxcars::Observability.track(
  event: 'action_completed',
  properties: { action_type: 'search' }
)

# After
Boxcars::Observability.track_observation(
  observation_with_user_context,
  event: 'action_completed',
  action_type: 'search'
)
```

## Benefits

1. **Better Debugging**: Quickly identify which user encountered an issue
2. **User Analytics**: Segment usage patterns by user type, role, or other attributes
3. **Compliance**: Track user actions for audit trails
4. **Support**: Faster issue resolution with user context
5. **Product Insights**: Understand how different user segments use AI features

## Best Practices

1. **Consistent Context**: Use the same user context structure across your application
2. **Helper Methods**: Create controller helpers to reduce code duplication
3. **Privacy First**: Only include necessary user data
4. **Error Handling**: Always handle cases where `current_user` might be nil
5. **Testing**: Write tests for both user and anonymous scenarios
6. **Documentation**: Document what user data you're tracking and why

## Troubleshooting

### Common Issues

**User context not appearing in analytics:**
- Ensure your observability backend is configured
- Check that you're using `track_observation` or passing the `observation` parameter to `track`
- Verify the observation actually has user context with `user_context?`

**Anonymous users causing errors:**
- Always check for `current_user` presence before creating user context
- Use helper methods that handle nil users gracefully

**Missing user data:**
- Ensure your `to_user_context` method returns a hash
- Check that the user object has the expected attributes

### Debug Example

```ruby
# Debug user context
observation = Boxcars::Observation.ok_with_user("Test", user_context: user_data)
puts "Has user context: #{observation.user_context?}"
puts "User context: #{observation.user_context.inspect}"
puts "Full observation: #{observation.to_h.inspect}"
```

This comprehensive user context system provides a clean, privacy-conscious way to associate user information with Boxcars operations, enabling better tracking, debugging, and analytics while maintaining backward compatibility.
