# frozen_string_literal: true

module Boxcars
  # Train's action to take.
  class TrainAction
    attr_accessor :boxcar, :boxcar_input, :log

    # record for a train action
    # @param boxcar [String] The boxcar to run.
    # @param log [String] The log of the action.
    # @param boxcar_input [String] The input to the boxcar.
    # @return [Boxcars::TrainAction] The train action.
    def initialize(boxcar:, log:, boxcar_input: nil)
      @boxcar_input = boxcar_input
      @boxcar = boxcar
      @log = log
    end

    # build a train action from a result
    # @param result [Boxcars::Result] The result to build from.
    # @param boxcar [String] The boxcar to run.
    # @param log [String] The log of the action.
    # @return [Boxcars::TrainAction] The train action.
    def self.from_result(result:, boxcar:, log:)
      new(boxcar:, boxcar_input: result.to_answer, log:)
    end
  end
end
