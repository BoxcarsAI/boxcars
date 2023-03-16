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
      code = text.split("```ruby\n").last.split("```").first.strip
      # code = text[8..-4].split("```").first.strip
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
        Result.new(status: :error,
                   explanation: "Error: expecting your response to begin with '```ruby'. Try answering the question again.")
      end
    end

    # our template
    CTEMPLATE = [
      syst("You can do basic math, but for any hard calculations that a human could not do ",
           "in their head, use the following approach instead. ",
           "Return code written in the Ruby programming language that prints the results. ",
           "If anyone gives you a hard math problem, just ",
           "use the following format and we’ll take care of the rest:\n",
           "${{Question with hard calculation.}}\n",
           "reply only with the following format:\n",
           "```ruby\n${{only Ruby code that prints the answer}}\n```\n",
           "```output\n${{Output of your code}}\n```\n\n",
           "Otherwise, you should use this simpler format:\n",
           "${{Question without hard calculation}}\n",
           "Answer: ${{Answer}}\n\n",
           "Do not give an explanation of the answer and make sure your answer starts with either 'Answer:' or '```ruby'."),
      syst("here is a hard example:\n", "the user asks: What is 37593 * 67?\n",
           "your answer: ```ruby\nputs(37593 * 67)\n```\n```output\n2518731\n```\nAnswer: 2518731"),
      syst("basic example:\n", "user asks: What is 2518731 + 0?\n", "you answer: Answer: 2518731"),
      syst("Begin."),
      user("%<question>s")
    ].freeze

    # The prompt to use for the engine.
    def my_prompt
      @conversation ||= Conversation.new(lines: CTEMPLATE)
      @my_prompt ||= ConversationPrompt.new(
        conversation: @conversation,
        input_variables: [:question],
        output_variables: [:answer])
    end
  end
end
