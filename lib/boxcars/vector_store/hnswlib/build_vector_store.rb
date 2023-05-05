# frozen_string_literal: true

require 'fileutils'
require 'hnswlib'
require 'json'

module Boxcars
  module VectorStore
    module Hnswlib
      class BuildVectorStore
        include VectorStore

        # This class is responsible for building the vector store for the hnswlib similarity search.
        # It will load the training data, generate the embeddings, and save the vector store.
        # It will also load the vector store into memory.
        # For later use, it will save the splitted document with index numbers to a json file.
        #
        # @param training_data_path [String] The path to the training data. Can be a glob pattern.
        # @param index_file_path [String] The path to the index file.
        # @param split_chunk_size [Integer] The number of documents to split the text into. default 2000
        # @option json_doc_file_path [String]. The json file containing the document text.
        #                                      if nil, it will reuse index file name.
        # @option force_rebuild [Boolean] Optional. If true, will rebuild the index even if it already exists.
        def initialize(
          training_data_path:,
          index_file_path:,
          split_chunk_size: 2000,
          json_doc_file_path: nil,
          force_rebuild: true
        )
          @training_data_path = training_data_path
          @index_file_path = index_file_path
          @split_chunk_size = split_chunk_size
          @json_doc_file_path = json_doc_file_path || index_file_path.gsub(/\.bin$/, '.json')
          @force_rebuild = force_rebuild
        end

        def call
          validate_params
          data = load_files
          documents = split_text_into_chunks(data)
          embeddings_with_config = generate_embeddings(documents)
          save_vector_store(embeddings_with_config)
          load_hnsw
        end

        private

        attr_reader :training_data_path, :index_file_path, :split_chunk_size, :json_doc_file_path, :force_rebuild

        def validate_params
          training_data_dir = File.dirname(training_data_path.gsub(/\*{1,2}/, ''))
          raise_error('training_data_path parent directory must exist') unless File.directory?(training_data_dir)
          raise_error('No files found at the training_data_path pattern') if Dir.glob(training_data_path).empty?

          index_dir = File.dirname(index_file_path)
          raise_error('index_file_path parent directory must exist') unless File.directory?(index_dir)

          raise_error('split_chunk_size must be an integer') unless split_chunk_size.is_a?(Integer)
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
          return true unless rebuild_required?

          docs = []
          data.each do |chunk|
            doc_output = Boxcars::VectorStore::SplitText.call(
              separator: "\n", chunk_size: split_chunk_size, chunk_overlap: 0, text: chunk
            )
            docs.concat(doc_output)
          end
          docs
        end

        def rebuild_required?
          hnswlib_config_json = "#{File.dirname(index_file_path)}/hnswlib_config.json"
          return true unless File.exist?(index_file_path)
          return true if File.exist?(index_file_path) && !File.exist?(hnswlib_config_json)
          return true if force_rebuild

          false
        end

        def generate_embeddings(documents)
          return true unless rebuild_required?

          puts "Initializing Store..."
          openai_client = Openai.open_ai_client
          embeddings_with_dim = Boxcars::VectorStore::EmbedViaOpenAI.call(texts: documents, client: openai_client)
          document_embeddings = embeddings_with_dim.map.with_index do |item, index|
            { doc_id: index, embedding: item[:embedding], document: documents[index] }
          end

          { document_embeddings: document_embeddings, dim: embeddings_with_dim.first[:dim] }
        end

        def save_vector_store(embeddings_with_config)
          return true unless rebuild_required?

          puts "Saving Vectorstore"
          Boxcars::VectorStore::Hnswlib::SaveToHnswlib.call(
            document_embeddings: embeddings_with_config[:document_embeddings],
            index_file_path: index_file_path,
            json_doc_file_path: json_doc_file_path,
            hnswlib_config: hnswlib_config(embeddings_with_config[:dim])
          )
          puts "VectorStore saved"
        end

        def hnswlib_config(dim)
          # dim: length of datum point vector that will be indexed.
          Boxcars::VectorStore::Hnswlib::HnswlibConfig.new(
            metric: "l2", max_item: 10000, dim: dim
          )
        end

        def load_hnsw
          puts "Loading Hnswlib"

          config_file = "#{File.dirname(index_file_path)}/hnswlib_config.json"
          json_config = parse_json_file(config_file)
          document_embeddings = parse_json_file(json_doc_file_path)

          search_index = ::Hnswlib::HierarchicalNSW.new(space: json_config[:metric], dim: json_config[:dim])
          search_index.load_index(index_file_path)

          { vector_store: search_index, document_embeddings: document_embeddings }
        end

        def parse_json_file(file_path)
          return [] if file_path.nil?

          file_content = File.read(file_path)
          JSON.parse(file_content, symbolize_names: true)
        rescue JSON::ParserError => e
          raise_error("Error parsing hnswlib_config.json: #{e.message}")
        end

        def raise_error(message)
          raise ::Boxcars::Error, message
        end
      end
    end
  end
end
