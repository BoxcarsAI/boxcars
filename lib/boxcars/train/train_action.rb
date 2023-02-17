# frozen_string_literal: true

module Boxcars
  # Train's action to take.
  class TrainAction
    attr_accessor :boxcar, :boxcar_input, :log

    def initialize(boxcar: nil, boxcar_input: nil, log: nil)
      @boxcar = boxcar
      @boxcar_input = boxcar_input
      @log = log
    end
  end
end
