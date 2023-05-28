# frozen_string_literal: true

module Boxcars
  module VectorStore
    module InMemory
      class BuildFromFiles
        include VectorStore

        # initialize the vector store with the following parameters:
        # @param params [Hash] A Hash containing the initial configuration.
        # @option params [Symbol] :embedding_tool The embedding tool to use.
        # @option params [String] :training_data_path The path to the training data files.
        # @option params [Integer] :split_chunk_size The number of characters to split the text into.
        # @return [Hash] vector_store: array of hashes with :content, :metadata, and :embedding keys
        def initialize(params)
          @split_chunk_size = params[:split_chunk_size] || 2000
          @training_data_path = File.absolute_path(params[:training_data_path])
          @embedding_tool = params[:embedding_tool] || :openai

          validate_params(embedding_tool, training_data_path)
          @memory_vectors = []
        end

        # @return [Hash] vector_store: array of hashes with :content, :metadata, and :embedding keys
        def call
          data = load_data_files(training_data_path)
          texts = split_text_into_chunks(data)
          vectors = generate_vectors(texts)
          add_vectors(vectors, texts)

          {
            type: :in_memory,
            vector_store: memory_vectors
          }
        end

        private

        attr_reader :split_chunk_size, :training_data_path, :embedding_tool, :memory_vectors

        def validate_params(embedding_tool, training_data_path)
          training_data_dir = File.dirname(training_data_path.gsub(/\*{1,2}/, ''))

          raise_argument_error('training_data_path parent directory must exist') unless File.directory?(training_data_dir)
          raise_argument_error('No files found at the training_data_path pattern') if Dir.glob(training_data_path).empty?

          return if %i[openai tensorflow].include?(embedding_tool)

          raise_argument_error('embedding_tool is invalid')
        end

        def add_vectors(vectors, texts)
          vectors.map.with_index do |vector, index|
            memory_vector = Document.new(
              content: texts[index],
              embedding: vector[:embedding],
              metadata: {
                doc_id: index,
                training_data_path: training_data_path
              }
            )
            memory_vectors << memory_vector
          end
        end
      end
    end
  end
end
