# frozen_string_literal: true

require 'fileutils'
require 'hnswlib'

module Boxcars
  module Embeddings
    module Hnswlib
      class BuildVectorStore
        include Embeddings

        attr_accessor :training_data_path, :index_file_path, :split_chunk_size, :doc_text_file_path

        def initialize(training_data_path:, index_file_path:, doc_text_file_path:, split_chunk_size: 2000)
          @training_data_path = training_data_path
          @index_file_path = index_file_path
          @split_chunk_size = split_chunk_size
          @doc_text_file_path = doc_text_file_path
        end

        def call
          validate_params
          data = load_files
          documents = split_text_into_chunks(data)
          embeddings_with_config = generate_embeddings(documents)
          configs = save_vector_store(embeddings_with_config)
          load_hnsw(configs)
        end

        private

        def validate_params
          training_data_dir = File.dirname(training_data_path.gsub(/\*{1,2}/, ''))
          raise_error 'training_data_path parent directory must exist' unless File.directory?(training_data_dir)
          raise_error 'No files found at the training_data_path pattern' if Dir.glob(training_data_path).empty?

          index_dir = File.dirname(index_file_path)
          raise_error 'index_file_path parent directory must exist' unless File.directory?(index_dir)

          raise_error 'split_chunk_size must be an integer' unless split_chunk_size.is_a?(Integer)
        end

        def load_files
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
            doc_output = Boxcars::Embeddings::SplitText.call(
              separator: "\n", chunk_size: split_chunk_size, chunk_overlap: 0, text: chunk
            )
            docs.concat(doc_output)
          end
          docs
        end

        def generate_embeddings(documents)
          puts "Initializing Store..."
          openai_client = OpenAI::Client.new(access_token: ENV.fetch('OPENAI_API_KEY', nil))

          embeddings_with_dim = Boxcars::Embeddings::EmbedViaOpenAI.call(texts: documents, openai_connection: openai_client)

          document_embeddings = embeddings_with_dim.map.with_index do |item, index|
            { doc_id: index, embedding: item[:embedding], document: documents[index] }
          end

          { document_embeddings: document_embeddings, dim: embeddings_with_dim.first[:dim] }
        end

        def save_vector_store(embeddings_with_config)
          puts "Saving Vectorstore"
          Boxcars::Embeddings::Hnswlib::SaveToHnswlib.call(
            document_embeddings: embeddings_with_config[:document_embeddings],
            index_file_path: index_file_path,
            doc_text_file_path: doc_text_file_path,
            hnswlib_config: hnswlib_config(embeddings_with_config[:dim])
          )
          puts "VectorStore saved"

          # space: The distance metric between vectors ('l2', 'dot', or 'cosine').
          { space: 'l2', dim: embeddings_with_config[:dim], document_embeddings: embeddings_with_config[:document_embeddings] }
        end

        def hnswlib_config(dim)
          # dim: length of datum point vector that will be indexed.
          Boxcars::Embeddings::Hnswlib::HnswlibConfig.new(
            metric: "l2", max_item: 10000, dim: dim
          )
        end

        def load_hnsw(configs)
          puts "Loading Hnswlib"
          search_index = ::Hnswlib::HierarchicalNSW.new(space: configs[:space], dim: configs[:dim])
          search_index.load_index(index_file_path)
          { vector_store: search_index, document_embeddings: configs[:document_embeddings] }
        end

        def raise_error(message)
          raise ::Boxcars::Error, message
        end
      end
    end
  end
end
