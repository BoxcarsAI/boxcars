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
  create_table "users", force: :cascade do |t|
    t.string   "name"

    t.timestamps
  end

  create_table "comments", force: :cascade do |t|
    t.text     "content"
    t.integer  "user_id"
    t.integer  "ticket_id"
    t.index ["ticket_id"], name: "index_comments_on_ticket_id"

    t.timestamps
  end
  create_table "tickets", force: :cascade do |t|
    t.string   "title"
    t.integer  "user_id"
    t.integer  "status", default: 0
    t.text     "body"

    t.timestamps
  end
end

# Set up helpdesk model classes
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

class User < ApplicationRecord
  has_many :tickets
  has_many :comments
end

class Comment < ApplicationRecord
  belongs_to :ticket
  belongs_to :user
end

class Ticket < ApplicationRecord
  belongs_to :user
  has_many :comments
  enum status: [:open, :closed]
end

# add some data
john = User.create(name: "John")
sally = User.create(name: "Sally")
# fred = User.create(name: "Fred")
Ticket.create(user: john, title: "First ticket", body: "This is the first ticket")
Ticket.create(user: sally, title: "Second ticket", body: "This is the second ticket")
Ticket.create(user: sally, title: "Third ticket", body: "This is the third ticket")
Ticket.first.comments.create(user: john, content: "This is a comment")
Ticket.first.comments.create(user: john, content: "This is johns second comment")
Ticket.last.comments.create(user: sally, content: "This is another comment")
Ticket.last.comments.create(user: sally, content: "This is yet another bingo comment")
