# frozen_string_literal: true

module Boxcars
  class Intelligence
    # Client for interacting with the Intelligence API
    class Client
      BASE_URL = "https://api.intelligence.com/v1"
      DEFAULT_TIMEOUT = 120

      def initialize(api_key:)
        @api_key = api_key
        @connection = Faraday.new(
          url: BASE_URL,
          headers: {
            "Content-Type" => "application/json",
            "Authorization" => "Bearer #{@api_key}"
          },
          request: {
            timeout: DEFAULT_TIMEOUT
          }
        )
      end

      # Generate a response from the Intelligence API
      def generate(parameters:)
        response = @connection.post("/generate") do |req|
          req.body = parameters.to_json
        end

        handle_response(response)
      end

      # Stream a response from the Intelligence API
      def stream(parameters:, &block)
        @connection.post("/generate") do |req|
          req.options.on_data = block
          req.headers["Accept"] = "text/event-stream"
          req.body = parameters.to_json
        end
      end

      private

      def handle_response(response)
        case response.status
        when 200
          JSON.parse(response.body)
        when 401
          raise KeyError, "Invalid API key"
        when 429
          raise ValueError, "Rate limit exceeded"
        when 400..499
          raise ArgumentError, "Bad request: #{response.body}"
        when 500..599
          raise Error, "Intelligence API server error"
        else
          raise Error, "Unexpected response: #{response.status}"
        end
      end
    end
  end
end
