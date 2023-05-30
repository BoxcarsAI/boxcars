# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A Boxcar that interprets a prompt and executes ruby code to do math
  class VectorAnswer < EngineBoxcar
    # the description of this engine boxcar
    DESC = "useful for when you need to answer questions from vector search results."

    attr_reader :embeddings, :vector_documents, :search_content

    # @param embeddings [Hash] The vector embeddings to use for this boxcar.
    # @param vector_documents [Hash] The vector documents to use for this boxcar.
    # @param engine [Boxcars::Engine] The engine to user for this boxcar. Can be inherited from a train if nil.
    # @param prompt [Boxcars::Prompt] The prompt to use for this boxcar. Defaults to built-in prompt.
    # @param kwargs [Hash] Any other keyword arguments to pass to the parent class.
    def initialize(embeddings:, vector_documents:, engine: nil, prompt: nil, **kwargs)
      the_prompt = prompt || my_prompt
      @embeddings = embeddings
      @vector_documents = vector_documents
      kwargs[:stop] ||= ["```output"]
      kwargs[:name] ||= "VectorAnswer"
      kwargs[:description] ||= DESC
      super(engine: engine, prompt: the_prompt, **kwargs)
    end

    # @param inputs [Hash] The inputs to use for the prediction.
    # @return Hash The additional variables for this boxcar.
    def prediction_additional(inputs)
      { search_content: get_search_content(inputs[:question]) }.merge super
    end

    private

    # @param results [Array] The results from the vector search.
    # @return [String] The content of the search results.
    def get_results_content(results)
      results&.map do |result|
        result[:document].content
      end.to_a.join("\n\n")
    end

    # return the content of the search results for count results
    # @params question [String] The question to search for.
    # @params count [Integer] The number of results to return.
    # @return [String] The content of the search results.
    def get_search_content(question, count: 1)
      search = Boxcars::VectorSearch.new(embeddings: embeddings, vector_documents: vector_documents)
      results = search.call query: question, count: count
      @search_content = get_results_content(results)
    end

    # our template
    CTEMPLATE = [
      syst("You are tasked with answering a question using these possibly relevant excerpts from a large volume of text:\n" \
           "```text\n%<search_content>s\n```\n\n",
           "Using the above, just answer the question as if you were answering directly."),
      user("%<question>s")
    ].freeze

    # The prompt to use for the engine.
    def my_prompt
      @conversation ||= Conversation.new(lines: CTEMPLATE)
      @my_prompt ||= ConversationPrompt.new(
        conversation: @conversation,
        input_variables: [:question],
        other_inputs: [:search_content],
        output_variables: [:answer])
    end
  end
end
