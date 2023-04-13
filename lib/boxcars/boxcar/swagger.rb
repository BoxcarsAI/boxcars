# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A Boxcar that interprets a prompt and executes API calls to get an answer.
  class Swagger < EngineBoxcar
    # the description of this engine boxcar
    DESC = "useful for when you need to make Open API calls to get an answer."

    attr_accessor :swagger_url, :context

    # @param swagger_url [String] The URL of the Open API Swagger file to use.
    # @param engine [Boxcars::Engine] The engine to user for this boxcar. Can be inherited from a train if nil.
    # @param prompt [Boxcars::Prompt] The prompt to use for this boxcar. Defaults to built-in prompt.
    # @param context [String] Additional context to use for the prompt.
    # @param kwargs [Hash] Any other keyword arguments to pass to the parent class.
    def initialize(swagger_url:, engine: nil, prompt: nil, context: "", **kwargs)
      @swagger_url = swagger_url
      @context = context
      the_prompt = prompt || my_prompt
      kwargs[:stop] ||= ["```output"]
      kwargs[:name] ||= "Swagger API"
      kwargs[:description] ||= DESC
      super(engine: engine, prompt: the_prompt, **kwargs)
    end

    # @return Hash The additional variables for this boxcar.
    def prediction_additional
      { swagger_url: swagger_url, context: context }.merge super
    end

    private

    def get_embedded_ruby_answer(text)
      code = text.split("```ruby\n").last.split("```").first.strip
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
      syst("Study this Open API Swagger file %<swagger_url>s\n",
           "and write a Ruby Program that prints the answer to the following questions using the appropriate API calls:\n",
           "Additional context that you might need in the Ruby program: (%<context>s)\n",
           "Use the following format:\n",
           "${{Question needing API calls and code}}\n",
           "reply only with the following format:\n",
           "```ruby\n${{Ruby code with API calls and code that prints the answer}}\n```\n",
           "```output\n${{Output of your code}}\n```\n\n",
           "Otherwise, if you know the answer and do not need any API calls, you should use this simpler format:\n",
           "${{Question not needing API calls}}\n",
           "Answer: ${{Answer}}\n\n",
           "Do not give an explanation of the answer and make sure your answer starts with either 'Answer:' or '```ruby'. ",
           "Make use of the rest-client gem to make your requests to the API. Just print the answer."),
      user("%<question>s")
    ].freeze

    # The prompt to use for the engine.
    def my_prompt
      @conversation ||= Conversation.new(lines: CTEMPLATE)
      @my_prompt ||= ConversationPrompt.new(
        conversation: @conversation,
        input_variables: [:question],
        other_inputs: [:context, :swagger_url],
        output_variables: [:answer])
    end
  end
end
