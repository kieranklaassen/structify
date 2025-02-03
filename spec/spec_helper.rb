# frozen_string_literal: true

require "bundler/setup"
require "structify"
require "active_support"
require "active_record"
require "sqlite3"

# Configure RSpec
RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  # Enable the focus filter
  config.filter_run_when_matching :focus

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Clean up any test data after each example
  config.after(:each) do
    # Add any cleanup code here
  end
end

# Configure ActiveRecord for in-memory SQLite
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

# Load database schema
ActiveRecord::Schema.define do
  create_table :articles, force: true do |t|
    t.string :title
    t.text :content
    t.json :extracted_data
    t.timestamps
  end
end
