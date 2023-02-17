# frozen_string_literal: true

module Boxcars
  # used by Boxcars to run ruby code
  class RubyREPL
    # Execute ruby code
    # @param code [String] The code to run
    def call(code:)
      puts "RubyREPL: #{code}".colorize(:red)
      output = ""
      IO.popen("ruby", "r+") do |io|
        io.puts code
        io.close_write
        output = io.read
      end
      puts "Answer: #{output}".colorize(:red, style: :bold)
      output
    end

    # Execute ruby code
    # @param command [String] The code to run
    def run(command)
      call(code: command)
    end
  end
end
