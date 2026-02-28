# frozen_string_literal: true

module Boxcars
  # A Boxcar that reads text from a URL.
  class URLText < Boxcar
    # Default description for this boxcar.
    DESC = "useful when you want to get text from a URL."

    # Create a URL text extraction boxcar.
    # @param name [String] The name of the boxcar. Defaults to classname.
    # @param description [String] A description of the boxcar.
    def initialize(name: "FetchURL", description: DESC)
      super
    end

    # Execute one URL text fetch using the normalized Boxcar input contract.
    # @param inputs [Hash] Expected to contain `:question` (or `"question"`) with a URL.
    # @return [Hash] `{ answer: Boxcars::Result }`.
    def call(inputs:)
      url = inputs[:question]
      parsed_url = URI.parse(url)
      { answer: do_encoding(get_answer(parsed_url)) }
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
