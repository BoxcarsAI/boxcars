# frozen_string_literal: true

require 'google_search_results'
module Boxcars
  # A Boxcar that uses the Google SERP API to get answers to questions.
  # It looks through SERP (search engine results page) results to find the answer.
  class GoogleSearch < Boxcar
    # the description of this boxcar
    SERPDESC = "useful for when you need to answer questions about current events." \
               "You should ask targeted questions"

    # implements a boxcar that uses the Google SerpAPI to get answers to questions.
    # @param name [String] The name of the boxcar. Defaults to classname.
    # @param description [String] A description of the boxcar. Defaults to SERPDESC.
    # @param serpapi_api_key [String] The API key to use for the SerpAPI. Defaults to Boxcars.configuration.serpapi_api_key.
    def initialize(name: "Search", description: SERPDESC, serpapi_api_key: nil)
      super(name: name, description: description)
      api_key = Boxcars.configuration.serpapi_api_key(serpapi_api_key: serpapi_api_key)
      ::GoogleSearch.api_key = api_key
    end

    # Get an answer from Google using the SerpAPI.
    # @param question [String] The question to ask Google.
    # @return [String] The answer to the question.
    def run(question)
      search = ::GoogleSearch.new(q: question)
      rv = find_answer(search.get_hash)
      puts "Question: #{question}"
      puts "Answer: #{rv}"
      rv
    end

    # Get the location of an answer from Google using the SerpAPI.
    # @param question [String] The question to ask Google.
    # @return [String] The location found.
    def get_location(question)
      search = ::GoogleSearch.new(q: question, limit: 3)
      rv = search.get_location
      puts "Question: #{question}"
      puts "Answer: #{rv}"
      rv
    end

    private

    ANSWER_LOCATIONS = [
      %i[answer_box answer],
      %i[answer_box snippet],
      [:answer_box, :snippet_highlighted_words, 0],
      %i[sports_results game_spotlight],
      %i[knowledge_graph description],
      [:organic_results, 0, :snippet_highlighted_words, 0],
      [:organic_results, 0, :snippet]
    ].freeze

    def find_answer(res)
      raise Error, "Got error from SerpAPI: {res[:error]}" if res[:error]

      ANSWER_LOCATIONS.each do |path|
        return res.dig(*path) if res.dig(*path)
      end
      "No good search result found"
    end
  end
end
