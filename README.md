# Structify

[![Gem Version](https://badge.fury.io/rb/structify.svg)](https://badge.fury.io/rb/structify)

A Ruby gem for extracting structured data from content using LLMs in Rails applications

## What is Structify?

Structify helps you extract structured data from unstructured content in your Rails apps:

- **Define extraction schemas** directly in your ActiveRecord models
- **Generate JSON schemas** to use with OpenAI, Anthropic, or other LLM providers
- **Store and validate** extracted data in your models
- **Access structured data** through typed model attributes

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
    field :title, :string
    field :summary, :text
    field :category, :string, enum: ["tech", "business", "science"]
    field :topics, :array, items: { type: "string" }
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
# Add to Gemfile
gem 'structify'
```

Then:
```bash
bundle install
```

## Database Setup

Add a JSON column to store extracted data:

```ruby
add_column :articles, :extracted_data, :jsonb  # PostgreSQL
# or
add_column :articles, :extracted_data, :json   # MySQL
```

## Usage

### Define Your Schema

```ruby
class Article < ApplicationRecord
  include Structify::Model

  schema_definition do
    version 1
    title "Article Extraction"
    
    field :title, :string, required: true
    field :summary, :text
    field :category, :string, enum: ["tech", "business", "science"]
    field :topics, :array, items: { type: "string" }
    field :metadata, :object, properties: {
      "author" => { type: "string" },
      "published_at" => { type: "string" }
    }
  end
end
```

### Get Schema for LLM API

Structify generates the JSON schema that you'll need to send to your LLM provider:

```ruby
# Get JSON Schema to send to OpenAI, Anthropic, etc.
schema = Article.json_schema
```

### Integration with LLM Services

You need to implement the actual LLM integration. Here's how you can integrate with popular services:

#### OpenAI Integration Example

```ruby
require "openai"

class OpenAiExtractor
  def initialize(api_key = ENV["OPENAI_API_KEY"])
    @client = OpenAI::Client.new(access_token: api_key)
  end
  
  def extract(content, model_class)
    # Get schema from Structify model
    schema = model_class.json_schema
    
    # Call OpenAI with structured outputs
    response = @client.chat(
      parameters: {
        model: "gpt-4o",
        response_format: { type: "json_object", schema: schema },
        messages: [
          { role: "system", content: "Extract structured information from the provided content." },
          { role: "user", content: content }
        ]
      }
    )
    
    # Parse and return the structured data
    JSON.parse(response.dig("choices", 0, "message", "content"), symbolize_names: true)
  end
end

# Usage
extractor = OpenAiExtractor.new
article = Article.find(123)
extracted_data = extractor.extract(article.content, Article)
article.update(extracted_data)
```

#### Anthropic Integration Example

```ruby
require "anthropic"

class AnthropicExtractor
  def initialize(api_key = ENV["ANTHROPIC_API_KEY"])
    @client = Anthropic::Client.new(api_key: api_key)
  end
  
  def extract(content, model_class)
    # Get schema from Structify model
    schema = model_class.json_schema
    
    # Call Claude with tool use
    response = @client.messages.create(
      model: "claude-3-opus-20240229",
      max_tokens: 1000,
      system: "Extract structured data based on the provided schema.",
      messages: [{ role: "user", content: content }],
      tools: [{
        type: "function",
        function: {
          name: "extract_data",
          description: "Extract structured data from content",
          parameters: schema
        }
      }],
      tool_choice: { type: "function", function: { name: "extract_data" } }
    )
    
    # Parse and return structured data
    JSON.parse(response.content[0].tools[0].function.arguments, symbolize_names: true)
  end
end
```

### Store & Access Extracted Data

```ruby
# Store LLM response in your model
article.update(response)

# Access via model attributes
article.title        # => "How AI is Changing Healthcare"
article.category     # => "tech"
article.topics       # => ["machine learning", "healthcare"]

# All data is in the JSON column
article.extracted_data  # => The complete JSON
```

## Field Types

Structify supports all standard JSON Schema types:

```ruby
field :name, :string             # String values
field :count, :integer           # Integer values
field :price, :number            # Numeric values (float/int)
field :active, :boolean          # Boolean values
field :metadata, :object         # JSON objects
field :tags, :array              # Arrays
```

## Field Options

```ruby
# Required fields
field :title, :string, required: true

# Enum values
field :status, :string, enum: ["draft", "published", "archived"]

# Array constraints
field :tags, :array,
  items: { type: "string" },
  min_items: 1,
  max_items: 5,
  unique_items: true

# Nested objects
field :author, :object, properties: {
  "name" => { type: "string", required: true },
  "email" => { type: "string" }
}
```

## Schema Versioning and Field Lifecycle

Structify provides a simple field lifecycle management system using a `versions` parameter:

```ruby
schema_definition do
  version 3
  
  # Fields for specific version ranges
  field :title, :string                       # Available in all versions (default behavior)
  field :legacy, :string, versions: 1...3     # Only in versions 1-2 (removed in v3)
  field :summary, :text, versions: 2          # Added in version 2 onwards
  field :content, :text, versions: 2..        # Added in version 2 onwards (endless range)
  field :temp_field, :string, versions: 2..3  # Only in versions 2-3
  field :special, :string, versions: [1, 3, 5] # Only in versions 1, 3, and 5
end
```

### Version Range Syntax

Structify supports several ways to specify which versions a field is available in:

| Syntax | Example | Meaning |
|--------|---------|---------|
| No version specified | `field :title, :string` | Available in all versions (default) |
| Single integer | `versions: 2` | Available from version 2 onwards |
| Range (inclusive) | `versions: 1..3` | Available in versions 1, 2, and 3 |
| Range (exclusive) | `versions: 1...3` | Available in versions 1 and 2 (not 3) |
| Endless range | `versions: 2..` | Available from version 2 onwards |
| Array | `versions: [1, 4, 7]` | Only available in versions 1, 4, and 7 |

### Handling Records with Different Versions

```ruby
# Create a record with version 1 schema
article_v1 = Article.create(title: "Original Article")

# Access with version 3 schema
article_v3 = Article.find(article_v1.id)

# Fields from v1 are still accessible
article_v3.title  # => "Original Article"

# Fields not in v1 raise errors
article_v3.summary  # => VersionRangeError: Field 'summary' is not available in version 1.
                    #    This field is only available in versions: 2 to 999.

# Check version compatibility
article_v3.version_compatible_with?(3)  # => false
article_v3.version_compatible_with?(1)  # => true

# Upgrade record to version 3
article_v3.summary = "Added in v3"
article_v3.save!  # Record version is automatically updated to 3
```


## Understanding Structify's Role

Structify is designed as a **bridge** between your Rails models and LLM extraction services:

### What Structify Does For You

- ✅ **Define extraction schemas** directly in your ActiveRecord models
- ✅ **Generate compatible JSON schemas** for OpenAI, Anthropic, and other LLM providers
- ✅ **Store and validate** extracted data against your schema
- ✅ **Provide typed access** to extracted fields through your models
- ✅ **Handle schema versioning** and backward compatibility

### What You Need To Implement

- 🔧 **API integration** with your chosen LLM provider (see examples above)
- 🔧 **Processing logic** for when and how to extract data
- 🔧 **Authentication** and API key management
- 🔧 **Error handling and retries** for API calls

This separation of concerns allows you to:
1. Use any LLM provider and model you prefer
2. Implement extraction logic specific to your application
3. Handle API access in a way that fits your application architecture
4. Change LLM providers without changing your data model

## License

[MIT License](https://opensource.org/licenses/MIT)