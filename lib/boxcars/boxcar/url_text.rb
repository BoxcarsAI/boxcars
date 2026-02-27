# frozen_string_literal: true

module Boxcars
  # A Boxcar that reads text from a URL.
  class URLText < Boxcar
    # the description of this boxcar
    DESC = "useful when you want to get text from a URL."

    # implements a boxcar that uses the Google SerpAPI to get answers to questions.
    # @param name [String] The name of the boxcar. Defaults to classname.
    # @param description [String] A description of the boxcar. Defaults to SERPDESC.
    def initialize(name: "FetchURL", description: DESC)
      super
    end

    # Get text from a url.
    # @param url [String] The url
    # @return [String] The text for the url.
    def run(url)
      url = URI.parse(url)
      do_encoding(get_answer(url))
    end

    private

    def do_encoding(answer)
      if answer.is_a?(Result)
        answer.explanation = answer.explanation.encode(xml: :text)
        answer
      else
        answer.encode(xml: :text)
      end
    end

    def html_to_text(url, response)
      Boxcars::OptionalDependency.require!("nokogiri", feature: "Boxcars::URLText HTML parsing")
      Nokogiri::HTML(response.body).css(%w[h1 h2 h3 h4 h5 h6 p a].join(",")).map do |e|
        itxt = e.inner_text.strip
        itxt = itxt.gsub(/[[:space:]]+/, " ") # remove extra spaces
        # next if itxt.nil? || itxt.empty?
        if e.name == "a"
          href = e.attributes["href"]&.value
          href = URI.join(url, href).to_s if href =~ %r{^/}
          "[#{itxt}](#{href})" # if e.attributes["href"]&.value =~ /^http/
        else
          itxt
        end
      end.compact.join("\n\n")
    end

    def get_answer(url)
      response = Net::HTTP.get_response(url)
      if response.is_a?(Net::HTTPSuccess)
        return Result.from_text(response.body) if response.content_type == "text/plain"

        if response.content_type == "text/html"
          # return only the top level text
          txt = html_to_text(url, response)
          Result.from_text(txt)
        else
          Result.from_text(response.body)
        end
      else
        Result.new(status: :error, explanation: "Error with url: #{response.code} #{response.message}")
      end
    end
  end
end
