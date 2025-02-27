# Structify

[![Gem Version](https://badge.fury.io/rb/structify.svg)](https://badge.fury.io/rb/structify)

## Extract structured data from your content using LLMs, right inside your Rails models

Structify is the building block you need when working with LLMs and Rails. It lets you define the structured data you want to extract directly in your ActiveRecord models, handles the schema generation for LLMs, and seamlessly stores the results.

```ruby
# 1. Define your existing Article model with extraction schema
class Article < ApplicationRecord
  include Structify::Model

  # Regular columns in your database: 
  #   - content: text             # Original unstructured content
  #   - extracted_data: jsonb     # Where Structify stores LLM extraction results

  # Define what you want to extract from the article content
  schema_definition do
    title "Article Extraction"
    description "Extract key information from articles"
    version 1
    
    field :title, :string, required: true
    field :summary, :text, description: "A brief summary of the article"
    field :category, :string, enum: ["tech", "business", "science"]
    field :topics, :array, items: { type: "string" }
  end
end

# 2. Use the JSON schema with your LLM service of choice
article = Article.find(123)                 # Get an existing article
json_schema = Article.json_schema           # Get the extraction schema

# Use any LLM service/adapter you prefer
llm_response = YourLlmService.extract(
  content: article.content, 
  schema: json_schema
)
# => { title: "AI Advances", summary: "Recent breakthroughs...", category: "tech", topics: ["machine learning", "neural networks"] }

# 3. Update the record with extracted data
article.update(llm_response)                # All fields are stored in extracted_data column

# 4. Access the structured data directly through your model
article.title        # => "AI Advances"
article.category     # => "tech"
article.topics       # => ["machine learning", "neural networks"]
article.extracted_data  # => The complete JSON with all extracted fields
```

## The Use Case: Why Structify Exists

**You have unstructured content in your Rails app that you want to analyze with LLMs.**

Maybe you're building:
- A content management system that needs to automatically extract topics and sentiment
- A customer support platform that tags and routes tickets based on content
- A research tool that extracts structured data from documents
- An email system that identifies action items and priorities

Structify provides the missing piece between your Rails models and LLM services by:

1. **Defining the extraction schema directly in your model** - Keep your schema and data access in one place
2. **Generating proper JSON schemas for LLM providers** - Works with OpenAI, Anthropic, and others
3. **Storing extracted data in a structured way** - No need for separate models or complex JSON handling
4. **Providing typed access to extraction results** - Use `article.title` instead of `article.extracted_data["title"]`
5. **Versioning your schemas** - As your needs evolve, your schemas can too

## How It Works

Structify is intentionally designed as a flexible building block:

1. **Define your schema** - Use the simple DSL to define what data to extract
2. **Get the JSON schema** - Use `YourModel.json_schema` to get a schema to send to any LLM
3. **Process with your LLM** - Use any LLM service, client, or adapter you prefer 
4. **Store the results** - Pass the LLM response to your model's attributes
5. **Access structured data** - Access the extracted data like any other model attribute

Structify doesn't include API clients or extraction logic on purpose. It focuses on doing one thing well - defining, validating, and storing LLM-extracted data in your Rails models.

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

Structify needs just one JSON column to store all your extracted data, keeping your database schema clean and simple.

### Step 1: Add the JSON column

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

### Step 2: Run the migration

```bash
rails db:migrate
```

That's it! This single column will store all the structured data extracted by your LLM, regardless of how many fields you define in your schema.

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

Structify supports all standard JSON Schema data types:

```ruby
# Basic types
field :name, :string                  # String values
field :description, :text             # Text (longer strings)
field :count, :integer                # Integer values
field :price, :number                 # Numeric values (both integers and floats)
field :active, :boolean               # Boolean values (true/false)

# Complex types
field :metadata, :object, properties: { # JSON objects with properties
  "author" => { type: "string" },
  "views" => { type: "integer" }
}

field :tags, :array, items: { type: "string" } # Arrays of values
```

## Schema Features

### Field Validation Options

Structify offers various validation options for your fields:

#### Required Fields

```ruby
field :title, :string, required: true
```

#### Enumerated Values

Restrict values to a predefined set (works with any type):

```ruby
field :status, :string, enum: ["pending", "approved", "rejected"]
field :priority, :integer, enum: [1, 2, 3]
field :score, :number, enum: [1.5, 2.5, 3.5]
field :flag, :boolean, enum: [true]
```

#### Field Descriptions

Add descriptions to help LLMs understand each field:

```ruby
field :summary, :text, 
  description: "A concise summary of the article's main points (3-5 sentences)"
```

#### Array Validation

For array fields, you can define constraints:

```ruby
field :tags, :array,
  items: { type: "string" },     # Define the type of items in the array
  min_items: 1,                  # Minimum number of items
  max_items: 5,                  # Maximum number of items
  unique_items: true             # Require unique items (no duplicates)
```

#### Object Properties and Validation

For object fields, you can define properties and specify which are required:

```ruby
field :author, :object, properties: {
  "name" => { type: "string", required: true },
  "email" => { type: "string", required: true },
  "age" => { type: "integer" },
  "bio" => { type: "string" }
}
```

You can also create complex nested object structures:

```ruby
field :user_data, :object, properties: {
  "profile" => { 
    type: "object", 
    properties: {
      "name" => { type: "string", required: true },
      "contact" => {
        type: "object",
        properties: {
          "email" => { type: "string", required: true },
          "phone" => { type: "string" }
        }
      }
    }
  },
  "preferences" => {
    type: "object",
    properties: {
      "theme" => { type: "string" },
      "notifications" => { type: "boolean" }
    }
  }
}
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

    # Required fields with basic types
    field :subject, :string, required: true
    field :summary, :text, required: true, 
          description: "A comprehensive summary of the email thread"
    
    # Fields with enumerated values
    field :sentiment, :string, enum: ["positive", "neutral", "negative"]
    field :priority, :integer, enum: [1, 2, 3], 
          description: "Priority level: 1 (high), 2 (medium), 3 (low)"
    
    # Array fields with constraints
    field :tags, :array, 
          items: { type: "string" },
          min_items: 1,
          max_items: 10,
          unique_items: true
    
    # Object fields with properties and required fields
    field :participants, :object, properties: {
      "names" => { type: "array", items: { type: "string" }, required: true },
      "count" => { type: "integer" },
      "organizer" => { 
        type: "object", 
        properties: {
          "name" => { type: "string", required: true },
          "email" => { type: "string", required: true },
          "role" => { type: "string" }
        }
      }
    }
    
    # JSON fields for complex data
    field :action_items, :array, items: {
      type: "object",
      properties: {
        "task" => { type: "string" },
        "assignee" => { type: "string" },
        "due_date" => { type: "string" }
      }
    }
    
    # Simple fields
    field :next_steps, :string
    field :completed, :boolean
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
summary.summary      # => "This email thread discusses the Q2 roadmap..."
summary.sentiment    # => "positive"
summary.priority     # => 1
summary.tags         # => ["roadmap", "planning", "q2"]
summary.participants # => { 
  "names" => ["Alice", "Bob"], 
  "count" => 2,
  "organizer" => {
    "name" => "Charlie",
    "email" => "charlie@example.com",
    "role" => "Team Lead"
  }
}
summary.action_items # => [{ "task" => "Update timeline", "assignee" => "Alice", "due_date" => "2023-04-15" }]
summary.next_steps   # => "Schedule follow-up meeting"
summary.completed    # => false
```

## Schema Information Methods

```ruby
# Get the JSON Schema
EmailSummary.json_schema
# => A complete JSON schema object to send to LLM APIs

# Get the schema version
EmailSummary.extraction_version  # => 2
```

## A Building Block Approach: What Structify Does & Doesn't Do

Structify is designed to be a flexible building block in your LLM-powered Rails application.

### What Structify Does:
- ✅ Define extraction schemas right in your ActiveRecord models
- ✅ Generate standard JSON schemas compatible with all major LLM providers
- ✅ Validate and store structured data in your existing models
- ✅ Provide typed access to extracted fields (`article.title` vs `article.extracted_data["title"]`)
- ✅ Handle versioning of your extraction schemas

### What Structify Doesn't Do (By Design):
- ❌ Make API calls to LLM providers (OpenAI, Anthropic, etc.)
- ❌ Process or analyze text content
- ❌ Handle authentication, API keys, or rate limiting
- ❌ Implement extraction logic or prompt engineering

### Why This Approach?
This separation of concerns gives you complete flexibility to:
- Use any LLM provider or model you prefer
- Implement your own extraction logic and prompting strategy
- Handle authentication and API access your way
- Build caching, retries, and error handling that fits your needs
- Easily swap out LLM providers without changing your data model

### Common Integration Patterns
Most users integrate Structify with LLMs in one of these ways:

1. **Direct API integration**: Call OpenAI, Anthropic, or other LLM APIs directly using their Ruby clients
2. **LLM framework/wrapper**: Use a framework like LangChain, LlamaIndex, or similar
3. **Custom service object**: Create a service object that handles the extraction process
4. **Background job**: Process extraction in the background using Sidekiq, etc.

### Example: Simple Integration with OpenAI

Here's an example service that integrates Structify with OpenAI:

```ruby
# app/services/openai_extraction_service.rb
class OpenaiExtractionService
  require "openai"
  
  def initialize
    @client = OpenAI::Client.new
  end
  
  def extract(record, content_field: :content)
    # Get the model class and content
    model_class = record.class
    content = record.send(content_field)
    
    # Get the JSON schema from Structify
    schema = model_class.json_schema
    
    # Prepare request to OpenAI
    response = @client.chat(
      parameters: {
        model: "gpt-4o",
        response_format: { type: "json_object", schema: schema },
        messages: [
          { role: "system", content: "Extract structured data from the provided content." },
          { role: "user", content: content }
        ]
      }
    )
    
    # Parse the response
    extracted_data = JSON.parse(response.dig("choices", 0, "message", "content"), symbolize_names: true)
    
    # Update the record with extracted data
    record.update(extracted_data)
    
    record
  end
end

# Usage in your application
article = Article.find(123)
OpenaiExtractionService.new.extract(article)

# Later, access the extracted data through your model
article.title    # => "AI Advances in Healthcare"
article.summary  # => "Recent breakthroughs in AI are transforming healthcare..."
```

### Example: Integration with Anthropic's Claude

```ruby
# app/services/anthropic_extraction_service.rb
class AnthropicExtractionService
  require "anthropic"
  
  def initialize
    @client = Anthropic::Client.new(api_key: ENV["ANTHROPIC_API_KEY"])
  end
  
  def extract(record, content_field: :content)
    # Get the model class and content
    model_class = record.class
    content = record.send(content_field)
    
    # Get the JSON schema from Structify
    schema = model_class.json_schema
    
    # Prepare request to Anthropic's Claude
    response = @client.messages.create(
      model: "claude-3-opus-20240229",
      max_tokens: 1000,
      system: "Extract structured data from the provided content.",
      messages: [
        { role: "user", content: content }
      ],
      tools: [
        {
          type: "function",
          function: {
            name: "extract_data",
            description: "Extract structured data from content",
            parameters: schema
          }
        }
      ],
      tool_choice: {
        type: "function",
        function: { name: "extract_data" }
      }
    )
    
    # Parse the response to get the structured data
    extracted_data = JSON.parse(response.content[0].tools[0].function.arguments, symbolize_names: true)
    
    # Update the record with extracted data
    record.update(extracted_data)
    
    record
  end
end
```

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