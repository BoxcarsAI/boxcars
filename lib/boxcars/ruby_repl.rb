# frozen_string_literal: true

module Boxcars
  # used by Boxcars to run ruby code
  class RubyREPL
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

    def run(command)
      call(code: command)
    end
  end
end
