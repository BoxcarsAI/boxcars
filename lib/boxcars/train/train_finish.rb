# frozen_string_literal: true

module Boxcars
  # Train's return value
  class TrainFinish
    attr_accessor :return_values, :log

    def initialize(return_values, log:)
      @return_values = return_values
      @log = log
    end
  end
end
