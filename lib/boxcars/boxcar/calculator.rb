# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A Boxcar that interprets a prompt and executes ruby code to do math
  class Calculator < EngineBoxcar
    # the description of this engine boxcar
    CALCDESC = "useful for when you need to answer questions about math"

    # @param engine [Boxcars::Engine] The engine to user for this boxcar. Can be inherited from a train if nil.
    # @param prompt [Boxcars::Prompt] The prompt to use for this boxcar. Defaults to built-in prompt.
    # @param kwargs [Hash] Any other keyword arguments to pass to the parent class.
    def initialize(engine: nil, prompt: nil, **kwargs)
      the_prompt = prompt || my_prompt
      kwargs[:stop] ||= ["```output"]
      kwargs[:name] ||= "Calculator"
      kwargs[:description] ||= CALCDESC
      super(engine: engine, prompt: the_prompt, **kwargs)
    end

    private

    def get_embedded_ruby_answer(text)
      code = text[8..-4].split("```").first.strip
      ruby_executor = Boxcars::RubyREPL.new
      ruby_executor.call(code: code)
    end

    def get_answer(text)
      case text
      when /^```ruby/
        get_embedded_ruby_answer(text)
      when /^Answer:/
        Result.from_text(text)
      else
        Result.new(status: :error, explanation: "Unknown format from engine: #{text}")
      end
    end

    # our template
    # rubocop:disable Style/RedundantHeredocDelimiterQuotes
    TEMPLATE = <<~'IPT'
      You are GPT-3, and you can't do math.
      You can do basic math, and your memorization abilities are impressive, but you can't do any complex calculations that a human could not do in their head. You also have an annoying tendency to just make up highly specific, but wrong, answers.
      So we hooked you up to a Ruby 3 kernel, and now you can execute code written in the Ruby programming language. If anyone gives you a hard math problem, just use this format and we’ll take care of the rest:

      Question: ${{Question with hard calculation.}}
      ```ruby
      ${{Code that prints what you need to know}}
      ```
      ```output
      ${{Output of your code}}
      ```
      Answer: ${{Answer}}

      Otherwise, use this simpler format:

      Question: ${{Question without hard calculation}}
      Answer: ${{Answer}}

      Begin.

      Question: What is 37593 * 67?
      ```ruby
      puts(37593 * 67)
      ```
      ```output
      2518731
      ```
      Answer: 2518731

      Question: what is 2518731 + 0?
      Answer: 2518731

      Question: %<question>s
    IPT
    # rubocop:enable Style/RedundantHeredocDelimiterQuotes

    # The prompt to use for the engine.
    def my_prompt
      @my_prompt ||= Prompt.new(input_variables: [:question], output_variables: [:answer], template: TEMPLATE)
    end
  end
end
