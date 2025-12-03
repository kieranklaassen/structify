# Structify

[![Gem Version](https://badge.fury.io/rb/structify.svg)](https://badge.fury.io/rb/structify)
[![CI](https://github.com/kieranklaassen/structify/actions/workflows/ci.yml/badge.svg)](https://github.com/kieranklaassen/structify/actions/workflows/ci.yml)

A Ruby gem for extracting structured data from content using LLMs in Rails applications

## What is Structify?

Structify helps you extract structured data from unstructured content in your Rails apps:

- **Define extraction schemas** directly in your ActiveRecord models using [ruby_llm-schema](https://github.com/danielfriis/ruby_llm-schema)
- **Generate JSON schemas** to use with OpenAI, Anthropic, or other LLM providers
- **Store extracted data** with AttrJson for typed model attributes
- **Validate LLM responses** with always-on schema validation

## Use Cases

- Extract metadata, topics, and sentiment from articles or blog posts
- Pull structured information from user-generated content
- Organize unstructured feedback or reviews into categorized data
- Convert emails or messages into actionable, structured formats
- Extract entities and relationships from documents

```ruby
# 1. Define extraction schema in your model
class Article < ApplicationRecord
  include Structify::Model

  schema_definition do
    name "ArticleExtraction"
    description "Extract article metadata"

    string :title
    string :summary, required: false
    string :category, enum: ["tech", "business", "science"]
    array :topics, of: :string
  end
end

# 2. Get schema for your LLM API
schema = Article.json_schema

# 3. Store LLM response in your model
article = Article.find(123)
article.update(llm_response)

# 4. Access extracted data
article.title    # => "AI Advances in 2023"
article.summary  # => "Recent developments in artificial intelligence..."
article.topics   # => ["machine learning", "neural networks", "computer vision"]
```

## Install

```ruby
gem 'structify'
```

Then:
```bash
bundle install
```

## Database Setup

Add a JSON column to store extracted data:

```ruby
add_column :articles, :json_attributes, :jsonb  # PostgreSQL
# or
add_column :articles, :json_attributes, :json   # MySQL
```

## Configuration

```ruby
# config/initializers/structify.rb
Structify.default_container_attribute = :json_attributes
```

## Usage

### Define Your Schema

Structify uses [ruby_llm-schema](https://github.com/danielfriis/ruby_llm-schema) for schema definitions:

```ruby
class Article < ApplicationRecord
  include Structify::Model

  schema_definition do
    name "ArticleExtraction"
    description "Extract article metadata"

    string :title
    string :summary, required: false
    string :category, enum: ["tech", "business", "science"]
    array :topics, of: :string, min_items: 1, max_items: 10

    object :author do
      string :name
      string :email, required: false
    end
  end
end
```

### Field Types

```ruby
string :name                    # String values
integer :count                  # Integer values
number :price                   # Numeric values (float)
boolean :active                 # Boolean values
array :tags, of: :string        # Arrays with item type
object :metadata do ... end     # Nested objects
```

### Field Options

```ruby
# Optional fields (required by default)
string :summary, required: false

# Enum values
string :status, enum: ["draft", "published", "archived"]

# Field descriptions for LLM context
string :title, description: "The article's main headline"

# Array constraints
array :tags, of: :string, min_items: 1, max_items: 5

# Nested objects
object :author do
  string :name
  string :email, required: false
end
```

### Get Schema for LLM API

```ruby
schema = Article.json_schema
# => { name: "ArticleExtraction", description: "...", properties: {...}, required: [...] }
```

### Integration with LLM Services

#### OpenAI Example

```ruby
require "openai"

client = OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])
schema = Article.json_schema

response = client.chat(
  parameters: {
    model: "gpt-4o",
    response_format: { type: "json_object", schema: schema },
    messages: [
      { role: "system", content: "Extract structured information from the provided content." },
      { role: "user", content: article.content }
    ]
  }
)

extracted = JSON.parse(response.dig("choices", 0, "message", "content"), symbolize_names: true)
article.update(extracted)
```

### Store & Access Extracted Data

```ruby
article.update(llm_response)

article.title     # => "How AI is Changing Healthcare"
article.category  # => "tech"
article.topics    # => ["machine learning", "healthcare"]
article.author    # => { "name" => "John Doe", "email" => "john@example.com" }
```

## Validation

Structify validates all LLM responses against your schema and raises specific exceptions:

```ruby
# Type validation
article.title = 123  # raises Structify::TypeMismatchError

# Required field validation
article.title = nil  # raises Structify::RequiredFieldError

# Enum validation
article.category = "invalid"  # raises Structify::EnumValidationError

# Array constraints
article.tags = []  # raises Structify::ArrayConstraintError (if min_items: 1)

# Object property validation
article.author = { "email" => "test@example.com" }  # raises Structify::ObjectValidationError (missing required name)
```

Handle validation errors:

```ruby
begin
  article.save!
rescue Structify::LLMValidationError => e
  # e.field_name - the field that failed validation
  # e.value - the invalid value
  # e.record - the model instance
  RetryExtractionJob.perform_later(article.id)
end
```

### Security Note

Validation error messages include field values for debugging purposes. If you extract sensitive data (PII, credentials, financial data), ensure your error handling sanitizes exceptions before logging:

```ruby
begin
  article.save!
rescue Structify::LLMValidationError => e
  # Log without sensitive data
  Rails.logger.error("Validation failed for field: #{e.field_name}")
  # Don't log e.message or e.value directly
end
```

## Versioning

Track schema versions for data migrations:

```ruby
class Article < ApplicationRecord
  include Structify::Model

  schema_definition do
    name "ArticleExtraction"
    version 2

    string :title
    string :summary
  end
end

# Class methods
Article.extraction_version  # => 2

# Instance methods
article.stored_version                # => 2 (from stored data)
article.version_compatible_with?(1)   # => true
article.version_compatible_with?(3)   # => false
```

## Upgrading from 0.x to 1.0

### Breaking Changes

1. **Schema DSL syntax changed** - Uses ruby_llm-schema DSL directly:
   ```ruby
   # OLD (0.x)
   schema_definition do
     field :title, :string, required: true
     field :count, :integer
   end

   # NEW (1.0)
   schema_definition do
     string :title
     integer :count, required: false
   end
   ```

2. **Fields are required by default** - In 1.0, all fields are required unless you specify `required: false`

3. **Versioning simplified** - The `versions:` field option has been removed. Use `version`, `stored_version`, and `version_compatible_with?` for schema-level versioning.

4. **SchemaSerializer removed** - Use `Model.json_schema` directly which returns the schema in LLM-compatible format.

## License

[MIT License](https://opensource.org/licenses/MIT)
