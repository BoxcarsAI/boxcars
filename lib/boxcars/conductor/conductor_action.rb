# frozen_string_literal: true

module Boxcars
  # Conductor's action to take.
  class ConductorAction
    attr_accessor :boxcar, :boxcar_input, :log

    def initialize(boxcar: nil, boxcar_input: nil, log: nil)
      @boxcar = boxcar
      @boxcar_input = boxcar_input
      @log = log
    end
  end
end
