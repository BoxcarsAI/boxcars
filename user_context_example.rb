#!/usr/bin/env ruby
# frozen_string_literal: true

# Example demonstrating how to use Boxcars with user context in a Rails-like application

require_relative 'lib/boxcars'

# Simulate a Rails-like current_user object
class User
  attr_reader :id, :email, :role, :name

  def initialize(id:, email:, role:, name:)
    @id = id
    @email = email
    @role = role
    @name = name
  end

  def to_user_context
    {
      id: id,
      email: email,
      role: role,
      name: name
    }
  end
end

# Simulate a Rails controller action
class ApplicationController
  attr_reader :current_user

  def initialize(current_user)
    @current_user = current_user
  end

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

# Example usage in a controller action
class ChatController < ApplicationController
  def ask_question
    question = "What is the capital of France?"

    begin
      # Simulate some boxcar processing
      puts "Processing question: #{question}"

      # Create observation with user context for successful operation
      observation = success_observation_with_user(
        "Question processed successfully: #{question}",
        question: question,
        processing_time_ms: 150,
        boxcar_type: "question_answering"
      )

      # Track the observation (this would send to your observability backend)
      Boxcars::Observability.track_observation(
        observation,
        event: 'question_processed',
        controller: 'ChatController',
        action: 'ask_question'
      )

      puts "✅ Success observation created with user context:"
      puts observation.to_json
      puts "\nUser context: #{observation.user_context}"
      puts "Has user context: #{observation.user_context?}"
    rescue StandardError => e
      # Create error observation with user context
      error_observation = error_observation_with_user(
        "Failed to process question: #{e.message}",
        question: question,
        error_class: e.class.name,
        error_message: e.message
      )

      # Track the error
      Boxcars::Observability.track_observation(
        error_observation,
        event: 'question_processing_error',
        controller: 'ChatController',
        action: 'ask_question'
      )

      puts "❌ Error observation created with user context:"
      puts error_observation.to_json
    end
  end
end

# Example usage with different user types
def demonstrate_user_context_examples
  puts "=" * 60
  puts "BOXCARS USER CONTEXT EXAMPLES"
  puts "=" * 60

  # Example 1: Admin user
  admin_user = User.new(
    id: 123,
    email: "admin@example.com",
    role: "admin",
    name: "Alice Admin"
  )

  puts "\n1. Admin User Example:"
  puts "-" * 30
  controller = ChatController.new(admin_user)
  controller.ask_question

  # Example 2: Regular user
  regular_user = User.new(
    id: 456,
    email: "user@example.com",
    role: "user",
    name: "Bob User"
  )

  puts "\n2. Regular User Example:"
  puts "-" * 30
  controller = ChatController.new(regular_user)
  controller.ask_question

  # Example 3: Anonymous user (no current_user)
  puts "\n3. Anonymous User Example:"
  puts "-" * 30
  controller = ChatController.new(nil)
  controller.ask_question

  # Example 4: Direct observation creation methods
  puts "\n4. Direct Observation Creation Examples:"
  puts "-" * 40

  user_context = admin_user.to_user_context

  # Using class methods
  obs1 = Boxcars::Observation.ok_with_user(
    "Direct success observation",
    user_context: user_context,
    operation: "direct_creation"
  )

  obs2 = Boxcars::Observation.err_with_user(
    "Direct error observation",
    user_context: user_context,
    operation: "direct_creation"
  )

  puts "Success observation: #{obs1.to_json}"
  puts "Error observation: #{obs2.to_json}"

  # Example 5: Using observations in train execution
  puts "\n5. Integration with Train Execution:"
  puts "-" * 40

  # This shows how you might modify train.rb to include user context
  # In practice, you'd pass user_context to the train and it would
  # create observations with that context

  observation_with_context = Boxcars::Observation.ok_with_user(
    "Train step completed successfully",
    user_context: user_context,
    train_step: "calculator",
    calculation_result: "42"
  )

  puts "Train observation with user context:"
  puts observation_with_context.to_json

  # Track it
  Boxcars::Observability.track_observation(
    observation_with_context,
    event: 'train_step_completed',
    train_type: 'zero_shot',
    step_number: 1
  )
end

# Configure a mock observability backend for demonstration
class MockObservabilityBackend
  def track(event:, properties:)
    puts "\n📊 TRACKING EVENT: #{event}"
    puts "Properties:"
    properties.each do |key, value|
      puts "  #{key}: #{value}"
    end
    puts "-" * 40
  end
end

# Set up the mock backend
Boxcars.configure do |config|
  config.observability_backend = MockObservabilityBackend.new
end

# Run the examples
if __FILE__ == $PROGRAM_NAME
  demonstrate_user_context_examples

  puts "\n#{"=" * 60}"
  puts "SUMMARY"
  puts "=" * 60
  puts <<~SUMMARY

    This example demonstrates how to integrate user context into Boxcars observations:

    1. **Enhanced Observation Class**:#{' '}
       - New methods: with_user, ok_with_user, err_with_user
       - Helper methods: user_context, user_context?

    2. **Enhanced Observability System**:
       - Automatic user context extraction and merging
       - PostHog-compatible $user_ prefixed properties
       - New track_observation method for easy observation tracking

    3. **Rails Integration Pattern**:
       - Helper methods in controllers to create observations with user context
       - Automatic fallback for anonymous users
       - Clean separation of concerns

    4. **Usage in Your Rails App**:
       ```ruby
       # In your controller
       observation = success_observation_with_user(
         "User performed action",
         action_type: "search",
         query: params[:q]
       )
    #{'   '}
       Boxcars::Observability.track_observation(observation)
       ```

    5. **Benefits**:
       - User actions are automatically tied to observations
       - Analytics systems can segment by user properties
       - Debugging is easier with user context
       - Privacy-conscious (you control what user data is included)
  SUMMARY
end
