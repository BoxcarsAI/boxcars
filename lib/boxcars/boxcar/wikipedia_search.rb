# frozen_string_literal: true

require "net/http"
module Boxcars
  # A Boxcar that uses the Wikipedia search API to get answers to questions.
  class WikipediaSearch < Boxcar
    # the description of this boxcar
    WDESC = "useful for when you need to answer questions about topics from Wikipedia." \
            "You should ask targeted questions"

    # Create a boxcar that uses Wikipedia search to answer questions.
    # @param name [String] The name of the boxcar. Defaults to classname.
    # @param description [String] A description of the boxcar.
    def initialize(name: "Wikipedia", description: WDESC)
      super
    end

    # Get an answer from Wikipedia search results.
    # @param question [String] The question to search.
    # @return [String] The answer to the question.
    def run(question)
      fetch_answer(question)
    end

    # Execute one Wikipedia search using the normalized Boxcar input contract.
    # @param inputs [Hash] Expected to contain `:question` (or `"question"`).
    # @return [Hash] `{ answer: String }`.
    def call(inputs:)
      question = inputs[:question] || inputs["question"]
      { answer: fetch_answer(question) }
    end

    # Execute multiple Wikipedia searches.
    # @param input_list [Array<Hash>] Input hashes for `#call`.
    # @return [Array<Hash>] One output hash per input hash.
    def apply(input_list:)
      input_list.map { |inputs| call(inputs:) }
    end

    private

    def fetch_answer(question)
      Boxcars.debug "Question: #{question}", :yellow
      uri = URI("https://en.wikipedia.org/w/api.php")
      params = { action: "query", list: "search", srsearch: question, format: "json" }
      uri.query = URI.encode_www_form(params)

      res = Net::HTTP.get_response(uri)
      raise "Error getting response from Wikipedia: #{res.body}" unless res.is_a?(Net::HTTPSuccess)

      response = JSON.parse res.body
      answer = response.dig("query", "search", 0, "snippet").to_s.gsub(/<[^>]*>/, "")
      pageid = response.dig("query", "search", 0, "pageid")
      answer = "#{answer}\nurl: https://en.wikipedia.org/?curid=#{pageid}" if pageid
      Boxcars.debug "Answer: #{answer}", :yellow, style: :bold
      answer
    end
  end
end
