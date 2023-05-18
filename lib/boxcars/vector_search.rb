# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # For Boxcars that use an engine to do their work.
  class VectorSearch
    def initialize(params)
      @vector_documents = params[:vector_documents]
      @embedding_tool = params[:embedding_tool] || :openai
      @vector_search_instance = vector_search_instance
      @openai_connection = params[:openai_connection] || default_connection(openai_access_token: openai_access_token)
    end

    def call(query:, count: 1)
      validate_query(query)
      query_vector = convert_query_to_vector(query)
      @vector_search_instance.call(query_vector: query_vector, count: count)
    end

    private

    attr_reader :vector_documents, :embedding_tool, :openai_connection

    def vector_search_instance
      case vector_documents[:type]
      when :hnswlib
        Boxcars::VectorStore::Hnswlib::Search.new(
          vector_documents: vector_documents
        )
      when :in_memory
        Boxcars::VectorStore::InMemory::Search.new(
          vector_documents: vector_documents
        )
      when :pgvector
        Boxcars::VectorStore::Pgvector::Search.new(
          vector_documents: vector_documents
        )
      else
        raise_argument_error('Unsupported vector store provided')
      end
    end

    def default_connection(openai_access_token: nil)
      Openai.open_ai_client(openai_access_token: openai_access_token)
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
