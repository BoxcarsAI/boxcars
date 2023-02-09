# frozen_string_literal: true

module Boxcars
  # Output of a single generation
  class Generation
    attr_accessor :text, :generation_info

    def initialize(text: nil, generation_info: nil)
      @text = text
      @generation_info = generation_info
    end
  end
end
