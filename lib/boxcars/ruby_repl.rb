# frozen_string_literal: true

module Boxcars
  # used by Boxcars to run ruby code
  class RubyREPL
    # Execute ruby code
    # @param code [String] The code to run
    def call(code:)
      Boxcars.debug "RubyREPL: #{code}", :yellow

      # wrap the code in an excption block so we can catch errors
      code = "begin\n#{code}\nrescue Exception => e\n  puts 'Error: ' + e.message\nend"
      output = ""
      IO.popen("ruby", "r+") do |io|
        io.puts code
        io.close_write
        output = io.read
      end
      if output =~ /^Error: /
        Boxcars.error output
        output
      end
      Boxcars.debug "Answer: #{output}", :yellow, style: :bold
      output
    end

    # Execute ruby code
    # @param command [String] The code to run
    def run(command)
      call(code: command)
    end
  end
end
