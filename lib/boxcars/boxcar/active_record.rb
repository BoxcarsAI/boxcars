# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A Boxcar that interprets a prompt and executes SQL code to get answers
  class ActiveRecord < EngineBoxcar
    # the description of this engine boxcar
    SQLDESC = "useful for when you need to query a Rails Active Record database."
    attr_accessor :connection, :input_key

    # @param engine [Boxcars::Engine] The engine to user for this boxcar. Can be inherited from a train if nil.
    # @param input_key [Symbol] The key to use for the input. Defaults to :question.
    # @param output_key [Symbol] The key to use for the output. Defaults to :answer.
    # @param kwargs [Hash] Any other keyword arguments to pass to the parent class. This can include
    #   :name, :description and :prompt
    def initialize(engine: nil, input_key: :question, output_key: :answer, **kwargs)
      @connection = connection
      @input_key = input_key
      the_prompt = kwargs[prompt] || my_prompt
      super(name: kwargs[:name] || "ActiveRecord",
            description: kwargs[:description] || SQLDESC,
            engine: engine,
            prompt: the_prompt,
            output_key: output_key)
    end

    # the input keys for the prompt
    # @return [Array<Symbol>] The input keys for the prompt.
    def input_keys
      [input_key]
    end

    # the output keys for the prompt
    # @return [Array<Symbol>] The output keys for the prompt.
    def output_keys
      [output_key]
    end

    # call the boxcar
    # @param inputs [Hash] The inputs to the boxcar.
    # @return [Hash] The outputs from the boxcar.
    def call(inputs:)
      t = predict(question: inputs[input_key], top_k: 5, model_info: model_info, stop: ["Answer:"]).strip
      answer = get_answer(t)
      puts answer.colorize(:magenta)
      { output_key => answer }
    end

    private

    def wanted_models(except_models: nil)
      except_models ||= ['ActiveRecord::InternalMetadata', 'ActiveRecord::SchemaMigration', 'ApplicationRecord']
      ::ActiveRecord::Base.descendants.reject { |m| except_models.include?(m.name) }
    end

    def models(except_models: nil)
      models = wanted_models(except_models: except_models).map(&:name)
      models.join(", ")
    end

    def model_info(except_models: nil)
      models = wanted_models(except_models: except_models)
      models.pretty_inspect
    end

    def get_active_record_answer(text)
      code = text[/^ARCode: (.*)/, 1]
      puts code.colorize(:yellow)
      begin
        # rubocop:disable Security/Eval
        output = eval code
        # rubocop:enable Security/Eval
        output = output.first if output.is_a?(Array) && output.length == 1
        "Answer: #{output}"
      rescue StandardError => e
        "Error: #{e.message}"
      end
    end

    def get_answer(text)
      case text
      when /^ARCode:/
        get_active_record_answer(text)
      when /^Answer:/
        text
      else
        raise Boxcars::Error "Unknown format from engine: #{text}"
      end
    end

    TEMPLATE = <<~IPT
      Given an input question, first create a syntactically correct Rails Active Record code to run,
      then look at the results of the code and return the answer. Unless the user specifies
      in her question a specific number of examples she wishes to obtain, always limit your code
      to at most %<top_k>s results. You can order the results by a relevant attribute
      to return the most interesting data examples.

      Never query for all the columns from a specific model, only ask for a the few relevant attributes given the question.

      Pay attention to use only the attribute names that you can see in the model description. Be careful to not query for attributes that do not exist.
      Also, pay attention to which attribute is in which model.

      Use the following format:
      Question: "Question here"
      ARCode: "Active Record code to run"
      Result: "Result of the Active Record code"
      Answer: "Final answer here"

      Only use the following Active Record models:
      %<model_info>s

      Question: %<question>s
    IPT

    # The prompt to use for the engine.
    def my_prompt
      @my_prompt ||= Prompt.new(input_variables: [:question, :top_k, :model_info], template: TEMPLATE)
    end
  end
end
