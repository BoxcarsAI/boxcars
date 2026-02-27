# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # For Boxcars that use an engine to do their work.
  class VectorSearch
    # initialize the vector search with the following parameters:
    # @param params [Hash] A Hash containing the initial configuration.
    # @option params [Hash] :vector_documents The vector documents to search.
    # example:
    # {
    #   type: :in_memory,
    #   vector_store: [
    #     Boxcars::VectorStore::Document.new(
    #       content: "hello",
    #       embedding: [0.1, 0.2, 0.3],
    #       metadata: { a: 1 }
    #     )
    #   ]
    # }
    def initialize(params)
      @vector_documents = params[:vector_documents]
      @embedding_tool = params[:embedding_tool] || :openai
      @vector_search_instance = vector_search_instance
      @openai_connection = params[:openai_connection] || default_connection(openai_access_token: params[:openai_access_token])
    end

    # @param query [String] The query to search for.
    # @param count [Integer] The number of results to return.
    # @return [Array] array of hashes with :document and :distance keys
    # @example
    #   [
    #     {
    #       document: Boxcars::VectorStore::Document.new(
    #         content: "hello",
    #         embedding: [0.1, 0.2, 0.3],
    #         metadata: { a: 1 }
    #       ),
    #       distance: 0.1
    #     }
    #   ]
    def call(query:, count: 1)
      validate_query(query)
      query_vector = convert_query_to_vector(query)
      @vector_search_instance.call(query_vector:, count:)
    end

    private

    attr_reader :vector_documents, :embedding_tool, :openai_connection

    def vector_search_instance
      case vector_documents[:type]
      when :hnswlib
        Boxcars::VectorStore::Hnswlib::Search.new(
          vector_documents:
        )
      when :in_memory
        Boxcars::VectorStore::InMemory::Search.new(
          vector_documents:
        )
      when :pgvector
        Boxcars::VectorStore::Pgvector::Search.new(
          vector_documents:
        )
      else
        raise_argument_error('Unsupported vector store provided')
      end
    end

    def default_connection(openai_access_token: nil)
      Openai.provider_client(openai_access_token:)
    end

    def validate_query(query)
      raise_argument_error('query must be a string') unless query.is_a?(String)
      raise_argument_error('query must not be empty') if query.empty?
    end

    def convert_query_to_vector(query)
      tool = embeddings_method(embedding_tool)
      res = tool[:klass].call(
        texts: [query], client: tool[:client]
      ).first
      res[:embedding]
    end

    def embeddings_method(embedding_tool)
      case embedding_tool
      when :openai
        { klass: Boxcars::VectorStore::EmbedViaOpenAI, client: openai_connection }
      when :tensorflow
        { klass: Boxcars::VectorStore::EmbedViaTensorflow, client: nil }
      end
    end

    def raise_argument_error(message)
      raise ::Boxcars::ArgumentError, message
    end
  end
end

require "boxcars/vector_store"
