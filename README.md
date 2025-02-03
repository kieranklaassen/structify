# Structify

[![Gem Version](https://badge.fury.io/rb/structify.svg)](https://badge.fury.io/rb/structify)

Structify is a Ruby gem that provides a simple DSL to define extraction schemas for LLM-powered models. It integrates seamlessly with Rails models, allowing you to specify versioning, assistant prompts, and field definitions—all in a clean, declarative syntax.

## Features

- 🎯 Simple DSL for defining LLM extraction schemas
- 🔄 Built-in versioning for schema evolution
- 📝 Support for custom assistant prompts
- 🏗️ JSON Schema generation for LLM validation
- 🔌 Seamless Rails/ActiveRecord integration
- 💾 Automatic JSON attribute handling

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'structify'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install structify
```

## Usage

### Basic Example

Here's a simple example of using Structify in a Rails model:

```ruby
class Article < ApplicationRecord
  include Structify::Model

  schema_definition do
    title "Article Extraction"
    description "Extract key information from articles"
    version 1

    assistant_prompt "Extract the following fields from the article content"
    llm_model "gpt-4"

    field :title, :string, required: true
    field :summary, :text, description: "A brief summary of the article"
    field :category, :string, enum: ["tech", "business", "science"]
  end
end
```

### Advanced Example

Here's a more complex example showing all available features:

```ruby
class EmailSummary < ApplicationRecord
  include Structify::Model

  schema_definition do
    version 2  # Increment this when making breaking changes
    title "Email Thread Extraction"
    description "Extracts key information from email threads"

    assistant_prompt <<~PROMPT
      You are an assistant that extracts concise metadata from email threads.
      Focus on producing a clear summary, action items, and sentiment analysis.
      If there are multiple participants, include their roles in the conversation.
    PROMPT

    llm_model "gpt-4"  # Supports any LLM model

    # Required fields
    field :subject, :string,
      required: true,
      description: "The main topic or subject of the email thread"

    field :summary, :text,
      required: true,
      description: "A concise summary of the entire thread"

    # Optional fields with enums
    field :sentiment, :string,
      enum: ["positive", "neutral", "negative"],
      description: "The overall sentiment of the conversation"

    field :priority, :string,
      enum: ["high", "medium", "low"],
      description: "The priority level based on content and tone"

    # Complex fields
    field :participants, :json,
      description: "List of participants and their roles"

    field :action_items, :json,
      description: "Array of action items extracted from the thread"

    field :next_steps, :string,
      description: "Recommended next steps based on the thread"
  end

  # You can still use regular ActiveRecord features
  validates :subject, presence: true
  validates :summary, length: { minimum: 10 }
end
```

### Accessing Schema Information

Structify provides several helper methods to access schema information:

```ruby
# Get the JSON Schema
EmailSummary.json_schema
# => {
#   name: "Email Thread Extraction",
#   description: "Extracts key information from email threads",
#   parameters: {
#     type: "object",
#     required: ["subject", "summary"],
#     properties: {
#       subject: { type: "string" },
#       summary: { type: "text" },
#       sentiment: {
#         type: "string",
#         enum: ["positive", "neutral", "negative"]
#       },
#       # ...
#     }
#   }
# }

# Get the current version
EmailSummary.extraction_version  # => 2

# Get the assistant prompt
EmailSummary.extraction_assistant_prompt
# => "You are an assistant that extracts concise metadata..."

# Get the LLM model
EmailSummary.extraction_llm_model  # => "gpt-4"
```

### Working with Extracted Data

Structify uses the `attr_json` gem to handle JSON attributes. All fields are stored in the `extracted_data` JSON column:

```ruby
# Create a new record with extracted data
summary = EmailSummary.create(
  subject: "Project Update",
  summary: "Team discussed Q2 goals",
  sentiment: "positive",
  priority: "high",
  participants: [
    { name: "Alice", role: "presenter" },
    { name: "Bob", role: "reviewer" }
  ]
)

# Access fields directly
summary.subject      # => "Project Update"
summary.sentiment    # => "positive"
summary.participants # => [{ name: "Alice", ... }]

# Validate enum values
summary.sentiment = "invalid"
summary.valid?  # => false
```

## Database Setup

Ensure your model has a JSON column named `extracted_data`:

```ruby
class CreateEmailSummaries < ActiveRecord::Migration[7.1]
  def change
    create_table :email_summaries do |t|
      t.json :extracted_data  # Required by Structify
      t.timestamps
    end
  end
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b feature/my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin feature/my-new-feature`)
5. Create a new Pull Request

Bug reports and pull requests are welcome on GitHub at https://github.com/kieranklaassen/structify.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Structify project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).

```

```
