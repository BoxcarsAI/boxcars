# frozen_string_literal: true

require 'openai'

module Boxcars
  module VectorStores
    class EmbedViaOpenAI
      include VectorStore

      attr_accessor :texts, :client, :model

      def initialize(texts:, client:, model: 'text-embedding-ada-002')
        validate_params(texts, client)
        @texts = texts
        @client = client
        @model = model
      end

      def call
        texts.map do |text|
          embedding = embedding_with_retry(model: model, input: strip_new_lines(text))
          {
            embedding: embedding,
            dim: embedding.size
          }
        end
      end

      private

      def validate_params(texts, client)
        raise_error 'texts must be an array of strings' unless texts.is_a?(Array) && texts.all? { |text| text.is_a?(String) }
        raise_error 'openai_connection must be an OpenAI::Client' unless client.is_a?(OpenAI::Client)
      end

      def embedding_with_retry(request)
        response = @client.embeddings(parameters: request)
        response['data'][0]['embedding']
      end

      def strip_new_lines(text)
        text.gsub("\n", ' ')
      end

      def raise_error(message)
        raise ::Boxcars::ValueError, message
      end
    end
  end
end
