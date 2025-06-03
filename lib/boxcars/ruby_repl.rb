# frozen_string_literal: true

module Boxcars
  # used by Boxcars to run ruby code
  class RubyREPL
    # Execute ruby code
    # @param code [String] The code to run
    def call(code:)
      Boxcars.debug "RubyREPL: #{code}", :yellow

      # wrap the code in an exception block so we can catch errors
      wrapped = "begin\n#{code}\nrescue Exception => e\n  puts 'Error: ' + e.message\nend"
      output = ""
      IO.popen("ruby", "r+") do |io|
        io.puts wrapped
        io.close_write
        output = io.read
      end
      if output =~ /^Error: /
        Boxcars.debug output, :red
        Result.from_error(output, code: code)
      elsif output.nil? || output.strip.empty?
        Result.from_error("The code you gave me did not print a result", code: code)
      else
        output = ::Regexp.last_match(1) if output =~ /^\s*Answer:\s*(.*)$/m
        Boxcars.debug "Answer: #{output}", :yellow, style: :bold
        Result.from_text(output, code: code)
      end
    end

    # Execute ruby code
    # @param command [String] The code to run
    def run(command)
      call(code: command)
    end
  end
end
