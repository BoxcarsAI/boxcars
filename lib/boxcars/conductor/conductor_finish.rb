# frozen_string_literal: true

module Boxcars
  # Conductor's return value
  class ConductorFinish
    attr_accessor :return_values, :log

    def initialize(return_values, log:)
      @return_values = return_values
      @log = log
    end
  end
end
