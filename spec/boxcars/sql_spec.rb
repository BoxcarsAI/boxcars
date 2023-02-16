# frozen_string_literal: true

RSpec.describe Boxcars::SQL do
  context "with in memory db" do
    # Instead of loading all of Rails, load the
    # particular Rails dependencies we need
    require 'sqlite3'
    require 'active_record'

    # Set up a database that resides in RAM
    ActiveRecord::Base.establish_connection(
      adapter: 'sqlite3',
      database: ':memory:'
    )

    # Set up database tables and columns
    ActiveRecord::Schema.define do
      create_table "comments", force: :cascade do |t|
        t.text     "content"
        t.string   "name"
        t.integer  "post_id"
        t.datetime "created_at", null: false
        t.datetime "updated_at", null: false
        t.index ["post_id"], name: "index_comments_on_post_id"
      end
      create_table "posts", force: :cascade do |t|
        t.string   "title"
        t.datetime "created_at", null: false
        t.datetime "updated_at", null: false
        t.text     "body"
      end
    end

    # Set up test model classes
    # rubocop:disable Lint/ConstantDefinitionInBlock
    # rubocop:disable RSpec/LeakyConstantDeclaration
    class ApplicationRecord < ActiveRecord::Base
      self.abstract_class = true
    end

    class Comment < ApplicationRecord
      belongs_to :post
    end

    class Post < ApplicationRecord
      has_many :comments
    end
    # rubocop:enable RSpec/LeakyConstantDeclaration
    # rubocop:enable Lint/ConstantDefinitionInBlock

    # add some data
    Post.create(title: "First post", body: "This is the first post")
    Post.create(title: "Second post", body: "This is the second post")
    Post.first.comments.create(name: "John", content: "This is a comment")
    Post.last.comments.create(name: "Jane", content: "This is another comment")
    Post.last.comments.create(name: "John", content: "This is yet another comment")

    conn = ActiveRecord::Base.connection
    engine = Boxcars::Openai.new
    boxcar = described_class.new(connection: conn, engine: engine)

    it "can count comments from john" do
      VCR.use_cassette("sql") do
        expect(boxcar.run("how many comments are there from John?")).to eq("Answer: [{\"COUNT(*)\"=>2}]")
      end
    end

    it "can find the last comment to the first post" do
      VCR.use_cassette("sql2") do
        expect(boxcar.run("What is the last comment for the first post?")).to include("\"content\"=>\"This is a comment\"")
      end
    end
  end
end
