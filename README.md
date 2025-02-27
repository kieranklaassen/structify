# Structify

[![Gem Version](https://badge.fury.io/rb/structify.svg)](https://badge.fury.io/rb/structify)

Define schema, validate, and store LLM-extracted data in your Rails applications

```ruby
# 1. Define your extraction schema
class Article < ApplicationRecord
  include Structify::Model

  schema_definition do
    title "Article Extraction"
    description "Extract key information from articles"
    version 1
    
    field :title, :string, required: true
    field :summary, :text, description: "A brief summary of the article"
    field :category, :string, enum: ["tech", "business", "science"]
  end
end

# 2. Call your LLM service with the generated JSON schema
json_schema = Article.json_schema

# Call LLM with structured output
llm_response = YourLlmService.extract_with_schema(
  content: article_text, 
  schema: json_schema
)

# 3. Create a record with the extracted data
article = Article.create(
  content: article_text,
  **llm_response  # Structify validates and stores in extracted_data
)

# 4. Access extracted fields directly
article.title    # => "Extracted Title"
article.summary  # => "This is a summary"
```

## The Problem

When using LLMs to extract structured data from text, you need to:

1. Define what fields to extract and their types/constraints
2. Create and maintain a JSON schema to send to LLM APIs (OpenAI, Anthropic, etc.)
3. Validate that the LLM's response matches your expected schema
4. Store the extracted data with proper typing in your database
5. Provide a clean way to access this data in your application

Structify solves all of these problems by providing a simple DSL to define extraction schemas that seamlessly integrate with your Rails models.

## How It Works

Structify serves as a bridge between your LLM extraction service and your Rails models:

1. **Define**: Create a schema for what you want to extract
2. **Extract**: Use the schema with your LLM service (OpenAI, Anthropic, etc.)
3. **Store**: Feed the LLM response to your model
4. **Access**: Work with the extracted data through your model

Structify doesn't make API calls to LLMs - it handles the schema definition, data validation, and storage parts of the process.

## Installation

Add to your Gemfile:

```ruby
gem 'structify'
```

Then:

```bash
bundle install
```

## Database Setup

Structify stores extracted fields in a JSON column. Add this column to your model:

```ruby
class AddExtractedDataToArticles < ActiveRecord::Migration[7.1]
  def change
    # PostgreSQL (recommended for best performance)
    add_column :articles, :extracted_data, :jsonb
    
    # Or for MySQL (>= 5.7)
    # add_column :articles, :extracted_data, :json
  end
end
```

## Workflow Example

### 1. Define Your Schema

```ruby
class Article < ApplicationRecord
  include Structify::Model

  schema_definition do
    title "Article Extraction"
    description "Extract key information from articles"
    version 1
    
    field :title, :string, required: true
    field :summary, :text, description: "A brief summary of the article"
    field :category, :string, enum: ["tech", "business", "science"]
  end
end
```

### 2. Generate Schema for LLM API

```ruby
# Get the schema to send to your LLM service
schema = Article.json_schema

# Example using OpenAI's Structured Outputs feature
openai_params = {
  model: "gpt-4o",
  response_format: { type: "json_object", schema: schema },
  messages: [
    { role: "system", content: "Extract structured data from this article." },
    { role: "user", content: article_text }
  ]
}

# Call OpenAI API
response = YourOpenAiService.call(openai_params)
extracted_data = JSON.parse(response.choices.first.message.content)

# OR for Anthropic's Claude
claude_params = {
  model: "claude-3-opus-20240229",
  system: "Extract structured data from this article.",
  max_tokens: 1000,
  tools: [
    {
      type: "function",
      function: {
        name: "extract_article_data",
        description: "Extract structured data from article text",
        parameters: schema
      }
    }
  ],
  messages: [
    { role: "user", content: article_text }
  ],
  tool_choice: {
    type: "function",
    function: { name: "extract_article_data" }
  }
}

# Call Anthropic API
response = YourAnthropicService.call(claude_params)
extracted_data = JSON.parse(response.content[0].tools[0].function.arguments)
```

### 3. Store and Access the Data

```ruby
# Store the extracted data (Structify validates against your schema)
article = Article.create(
  content: article_text,
  **extracted_data  # Pass all extracted fields
)

# Access extracted fields directly
article.title      # => "AI Advances"
article.summary    # => "Recent developments in AI technology"
article.category   # => "tech"

# All extracted data is stored in the JSON column
article.extracted_data
# => {"title":"AI Advances","summary":"Recent developments in AI technology","category":"tech"}
```

## Available Field Types

Structify supports all standard types for schema fields:

```ruby
field :name, :string
field :description, :text
field :rating, :integer
field :score, :float
field :is_featured, :boolean
field :metadata, :json
field :published_at, :datetime
```

## Schema Features

### Field Validation

Define field requirements and enumerations:

```ruby
field :priority, :string, 
  required: true,
  enum: ["high", "medium", "low"]
```

### Field Descriptions

Add descriptions to help LLMs understand each field:

```ruby
field :summary, :text, 
  description: "A concise summary of the article's main points (3-5 sentences)"
```

### Schema Versioning

Track schema changes with versioning:

```ruby
schema_definition do
  version 2  # Increment when making breaking changes
  # ...
end
```

## Complete Example

Here's a comprehensive example showing the full extraction workflow:

```ruby
# 1. Define your model with an extraction schema
class EmailSummary < ApplicationRecord
  include Structify::Model

  schema_definition do
    version 2
    title "Email Thread Analysis"
    description "Extracts key information from email threads"

    # Required fields
    field :subject, :string, required: true
    field :summary, :text, required: true
    
    # Optional fields with enums
    field :sentiment, :string, enum: ["positive", "neutral", "negative"]
    field :priority, :string, enum: ["high", "medium", "low"]
    
    # Complex fields
    field :participants, :json
    field :action_items, :json
    field :next_steps, :string
  end

  # Regular ActiveRecord validations still work
  validates :summary, length: { minimum: 10 }
end

# 2. Get schema information to pass to your LLM service
schema = EmailSummary.json_schema

# 3. Call your LLM service with OpenAI Structured Outputs
openai_params = {
  model: "gpt-4",
  response_format: { type: "json_object", schema: schema },
  messages: [
    { role: "system", content: "Extract structured data from this email thread." },
    { role: "user", content: email_thread }
  ]
}
response = YourOpenAiService.call(openai_params)
llm_response = JSON.parse(response.choices.first.message.content)

# 4. Create record with extracted data
summary = EmailSummary.create(
  original_email: email_thread,  # Your regular column
  **llm_response                  # All extracted fields
)

# 5. Access the extracted data
summary.subject      # => "Project Update"
summary.sentiment    # => "positive"
summary.participants # => [{ name: "Alice", role: "presenter" }, ...]
```

## Schema Information Methods

```ruby
# Get the JSON Schema
EmailSummary.json_schema
# => A complete JSON schema object to send to LLM APIs

# Get the schema version
EmailSummary.extraction_version  # => 2
```

## What Structify Doesn't Do

Structify intentionally **does not**:
- Make API calls to OpenAI, Anthropic, or other LLM providers
- Process or analyze text itself
- Handle authentication or API keys for LLM services

These concerns are kept separate so you can:
- Use any LLM provider or model you prefer (OpenAI, Anthropic, etc.)
- Use Structured Outputs (OpenAI) or tool calling (Anthropic) to ensure structured responses
- Implement your own caching, retries, and error handling for API calls
- Keep your authentication details separate from your data models

## Under The Hood

Structify uses the `attr_json` gem to handle JSON attributes. All fields you define are automatically set up as attr_json attributes mapped to the `extracted_data` JSON column.

## Development

```bash
# Install dependencies
bin/setup

# Run tests
bundle exec rake spec

# Run console
bin/console

# Install locally
bundle exec rake install
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Run tests (`bundle exec rake spec`)
4. Commit changes (`git commit -am 'Add feature'`)
5. Push to branch (`git push origin feature/my-feature`)
6. Create a Pull Request

Bug reports and pull requests are welcome on GitHub at https://github.com/kieranklaassen/structify.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Structify project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).