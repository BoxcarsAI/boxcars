# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  module VectorStore
    module ClassMethods
      VectorStoreError = Class.new(StandardError)

      def call(*args, **kw_args)
        new(*args, **kw_args).call
      end
    end

    def self.included(base)
      base.extend(ClassMethods)
    end

    private

    attr_reader :embedding_tool

    def generate_vectors(texts)
      @embedding_tool = embedding_tool || :openai

      embeddings_method[:klass]
        .call(
          texts: texts, client: embeddings_method[:client]
        )
        .map { |item| item.transform_keys(&:to_sym) }
    end

    def embeddings_method
      case @embedding_tool
      when :openai
        { klass: Boxcars::VectorStore::EmbedViaOpenAI, client: openai_client }
      when :tensorflow
        { klass: Boxcars::VectorStore::EmbedViaTensorflow, client: nil }
      end
    end

    # Get the OpenAI client
    # @param openai_access_token [String] the OpenAI access token
    # @return [OpenAI::Client]
    def openai_client(openai_access_token: nil)
      @openai_client ||= Openai.open_ai_client(openai_access_token: openai_access_token)
    end

    def raise_argument_error(message)
      raise ::Boxcars::ArgumentError, message
    end

    def parse_json_file(file_path)
      return [] if file_path.nil?

      file_content = File.read(file_path)
      JSON.parse(file_content, symbolize_names: true)
    rescue JSON::ParserError => e
      raise_argument_error("Error parsing #{file_path}: #{e.message}")
    end

    def load_data_files(training_data_path)
      data = []
      files = Dir.glob(training_data_path)
      raise_error "No files found at #{training_data_path}" if files.empty?

      files.each do |file|
        data << File.read(file)
      end
      puts "Added #{files.length} files to data. Splitting text into chunks..."
      data
    end

    def split_text_into_chunks(data)
      docs = []
      data.each do |chunk|
        doc_output = Boxcars::VectorStore::SplitText.call(
          separator: "\n", chunk_size: split_chunk_size, chunk_overlap: 0, text: chunk
        )
        docs.concat(doc_output)
      end
      docs
    end
  end
end

require_relative "vector_store/document"
require_relative "vector_store/embed_via_open_ai"
require_relative "vector_store/embed_via_tensorflow"
require_relative "vector_store/split_text"
require_relative "vector_store/hnswlib/load_from_disk"
require_relative "vector_store/hnswlib/save_to_hnswlib"
require_relative "vector_store/hnswlib/build_from_files"
require_relative "vector_store/hnswlib/search"
require_relative "vector_store/in_memory/build_from_files"
require_relative "vector_store/in_memory/build_from_document_array"
require_relative "vector_store/in_memory/search"
