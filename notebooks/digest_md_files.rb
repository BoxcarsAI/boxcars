require 'dotenv/load'
lib_path = File.expand_path('../lib', __dir__)
$LOAD_PATH.unshift(lib_path) unless $LOAD_PATH.include?(lib_path)
require 'boxcars'

storage = Boxcars::Embeddings::Hnswlib::BuildVectorStore.call(
  training_data_path: './Notion_DB/**/*.md',
  index_file_path: './hnswlib_notion_db_index.bin',
  doc_text_file_path: './hnswlib_notion_db_doc_text.json'
)

openai_client = OpenAI::Client.new(access_token: ENV.fetch('OPENAI_API_KEY', nil))

similarity_search = Boxcars::Embeddings::SimilaritySearch.new(
  embeddings: storage[:document_embeddings],
  vector_store: storage[:vector_store],
  openai_connection: openai_client
)

similarity_search.call(query: 'What is the work from home policy')
