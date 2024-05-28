# frozen_string_literal: true

require "net/http"
module Boxcars
  # A Boxcar that uses the Wikipedia search API to get answers to questions.
  class WikipediaSearch < Boxcar
    # the description of this boxcar
    WDESC = "useful for when you need to answer questions about topics from Wikipedia." \
            "You should ask targeted questions"

    # implements a boxcar that uses the Wikipedia Search to get answers to questions.
    # @param name [String] The name of the boxcar. Defaults to classname.
    # @param description [String] A description of the boxcar. Defaults to SERPDESC.
    # @param serpapi_api_key [String] The API key to use for the SerpAPI. Defaults to Boxcars.configuration.serpapi_api_key.
    def initialize(name: "Wikipedia", description: WDESC)
      super
    end

    # Get an answer from Google using the SerpAPI.
    # @param question [String] The question to ask Google.
    # @return [String] The answer to the question.
    def run(question)
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
