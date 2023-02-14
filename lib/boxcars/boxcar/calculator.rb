# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A Boxcar that interprets a prompt and executes ruby code to do math
  class Calculator < LLMBoxcar
    CALCDESC = "useful for when you need to answer questions about math"
    attr_accessor :input_key

    # @param prompt [Boxcars::LLMPrompt] The prompt to use for this boxcar.
    # @param name [String] The name of the boxcar. Defaults to classname.
    # @param description [String] A description of the boxcar.
    # @param llm [Boxcars::LLM] The LLM to user for this boxcar. Can be inherited from a conductor if nil.
    # @param input_key [Symbol] The key to use for the input. Defaults to :question.
    # @param output_key [Symbol] The key to use for the output. Defaults to :answer.
    def initialize(llm: nil, prompt: nil, input_key: :question, output_key: :answer, **kwargs)
      # def initialize(llm:, prompt: my_prompt, input_key: :question, output_key: :answer, **kwargs)
      @input_key = input_key
      the_prompt = prompt || my_prompt
      super(name: kwargs[:name] || "Calculator",
            description: kwargs[:description] || CALCDESC,
            llm: llm,
            prompt: the_prompt,
            output_key: output_key)
    end

    def input_keys
      [input_key]
    end

    def output_keys
      [output_key]
    end

    def call(inputs:)
      t = predict(question: inputs[input_key], stop: ["```output"]).strip
      answer = get_answer(t)
      puts answer.colorize(:magenta)
      { output_key => answer }
    end

    private

    def get_embedded_ruby_answer(text)
      code = text[8..-4].split("```").first.strip
      ruby_executor = Boxcars::RubyREPL.new
      output = ruby_executor.call(code: code).strip
      "Answer: #{output}"
    end

    def get_answer(text)
      case text
      when /^```ruby/
        get_embedded_ruby_answer(text)
      when /^Answer:/
        text
      else
        raise Boxcars::Error "Unknown format from LLM: #{text}"
      end
    end

    TEMPLATE = <<~IPT
      You are GPT-3, and you can't do math.

      You can do basic math, and your memorization abilities are impressive, but you can't do any complex calculations that a human could not do in their head. You also have an annoying tendency to just make up highly specific, but wrong, answers.

      So we hooked you up to a Ruby 3 kernel, and now you can execute ruby code. If anyone gives you a hard math problem, just use this format and we’ll take care of the rest:

      Question: ${{Question with hard calculation.}}
      ```ruby
      ${{Code that prints what you need to know}}
      ```

      Otherwise, use this simpler format:

      Question: ${{Question without hard calculation}}
      Answer: ${{Answer}}

      Begin.

      Question: What is 37593 * 67?
      ```ruby
      puts(37593 * 67)
      ```

      Question: what is 2518731 + 0?
      Answer: 2518731

      Question: %<question>s
    IPT

    # The prompt to use for the LLM.
    def my_prompt
      @my_prompt ||= LLMPrompt.new(input_variables: [:question], template: TEMPLATE)
    end
  end
end
