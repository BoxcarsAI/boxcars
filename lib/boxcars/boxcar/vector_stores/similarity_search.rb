# frozen_string_literal: true

require 'hnswlib'

module Boxcars
  module VectorStores
    class SimilaritySearch
      def initialize(embeddings:, vector_store:, openai_connection: nil, openai_access_token: nil)
        @embeddings = embeddings
        @vector_store = vector_store
        @similarity_search_instance = create_similarity_search_instance
        @openai_connection = openai_connection || default_connection(openai_access_token: openai_access_token)
      end

      def call(query:)
        validate_query(query)
        query_vector = convert_query_to_vector(query)
        @similarity_search_instance.call(query_vector)
      end

      private

      attr_reader :embeddings, :vector_store, :openai_connection

      def default_connection(openai_access_token: nil)
        access_token = Boxcars.configuration.openai_access_token(openai_access_token: openai_access_token)
        organization_id = Boxcars.configuration.organization_id
        ::OpenAI::Client.new(access_token: access_token, organization_id: organization_id)
      end

      def validate_query(query)
        raise_error 'query must be a string' unless query.is_a?(String)
        raise_error 'query must not be empty' if query.empty?
      end

      def convert_query_to_vector(query)
        Boxcars::VectorStores::EmbedViaOpenAI.call(texts: [query], openai_connection: openai_connection).first[:embedding]
      end

      def create_similarity_search_instance
        case vector_store
        when ::Hnswlib::HierarchicalNSW
          Boxcars::VectorStores::Hnswlib::HnswlibSearch.new(
            vector_store: vector_store,
            options: { json_doc_path: embeddings, num_neighbors: 2 }
          )
        else
          raise_error 'Unsupported vector store provided'
        end
      end

      def raise_error(message)
        raise ArgumentError, message
      end
    end
  end
end
