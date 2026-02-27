# frozen_string_literal: true

require_relative "openai_client"

module Boxcars
  OpenAICompatibleClient = OpenAIClient unless const_defined?(:OpenAICompatibleClient, false)
end
