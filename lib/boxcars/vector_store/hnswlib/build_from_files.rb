# frozen_string_literal: true

require 'fileutils'
require 'hnswlib'
require 'json'

module Boxcars
  module VectorStore
    module Hnswlib
      # This class is responsible for building the vector store for the hnswlib similarity search.
      # It will load the training data, generate the embeddings, and save the vector store.
      # It will also load the vector store into memory.
      # For later use, it will save the splitted document with index numbers to a json file.
      class BuildFromFiles
        include VectorStore

        def initialize(params)
          @split_chunk_size = params[:split_chunk_size] || 2000
          @training_data_path = File.absolute_path(params[:training_data_path])
          @index_file_path = File.absolute_path(params[:index_file_path])

          validate_params(@training_data_path, @index_file_path, split_chunk_size)

          @json_doc_file_path = absolute_json_doc_file_path(@index_file_path, params[:json_doc_file_path])
          @force_rebuild = params[:force_rebuild] || true
          @hnsw_vectors = []
        end

        def call
          if !force_rebuild && File.exist?(index_file_path)
            load_existing_vector_store
          else
            puts "Building Hnswlib vector store..."
            data = load_data_files(training_data_path)
            Boxcars.debug("Loaded #{data.length} files from #{training_data_path}")
            texts = split_text_into_chunks(data)
            Boxcars.debug("Split #{data.length} files into #{texts.length} chunks")
            vectors = generate_vectors(texts)
            Boxcars.debug("Generated #{vectors.length} vectors")
            add_vectors(vectors, texts)
            Boxcars.debug("Added #{vectors.length} vectors to vector store")
            save_vector_store

            {
              type: :hnswlib,
              vector_store: hnsw_vectors
            }
          end
        end

        private

        attr_reader :training_data_path, :index_file_path, :split_chunk_size, :json_doc_file_path, :force_rebuild, :hnsw_vectors

        def validate_params(training_data_path, index_file_path, split_chunk_size)
          training_data_dir = File.dirname(training_data_path.gsub(/\*{1,2}/, ''))

          raise_argument_error('training_data_path parent directory must exist') unless File.directory?(training_data_dir)
          raise_argument_error('No files found at the training_data_path pattern') if Dir.glob(training_data_path).empty?

          index_dir = File.dirname(index_file_path)

          raise_argument_error('index_file_path parent directory must exist') unless File.directory?(index_dir)
          raise_argument_error('split_chunk_size must be an integer') unless split_chunk_size.is_a?(Integer)
        end

        def absolute_json_doc_file_path(index_file_path, json_doc_file_path)
          return index_file_path.gsub(/\.bin$/, '.json') unless json_doc_file_path

          File.absolute_path(json_doc_file_path)
        end

        def add_vectors(vectors, texts)
          vectors.map.with_index do |vector, index|
            hnsw_vector = Document.new(
              content: texts[index],
              embedding: vector[:embedding],
              metadata: {
                doc_id: index,
                dim: vector[:dim],
                metric: 'l2',
                max_item: 10000,
                index_file_path: index_file_path,
                json_doc_file_path: json_doc_file_path
              }
            )
            hnsw_vectors << hnsw_vector
          end
        end

        def save_vector_store
          Boxcars::VectorStore::Hnswlib::SaveToHnswlib.call(hnsw_vectors)
        end

        def load_existing_vector_store
          Boxcars::VectorStore::Hnswlib::LoadFromDisk.call(
            index_file_path: index_file_path,
            json_doc_file_path: json_doc_file_path
          )
        end
      end
    end
  end
end
