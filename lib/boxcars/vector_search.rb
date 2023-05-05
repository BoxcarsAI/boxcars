# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # For Boxcars that use an engine to do their work.
  class VectorSearch < Boxcar
    Error = Class.new(StandardError)
  end
end

require "boxcars/vector_store"
