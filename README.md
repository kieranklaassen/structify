# Structify

[![Gem Version](https://badge.fury.io/rb/structify.svg)](https://badge.fury.io/rb/structify)
[![CI](https://github.com/kieranklaassen/structify/actions/workflows/ci.yml/badge.svg)](https://github.com/kieranklaassen/structify/actions/workflows/ci.yml)

A Ruby gem for extracting structured data from content using LLMs in Rails applications

## What is Structify?

Structify helps you extract structured data from unstructured content in your Rails apps:

- **Define extraction schemas** directly in your ActiveRecord models
- **Generate JSON schemas** to use with OpenAI, Anthropic, or other LLM providers
- **Store and validate** extracted data with ActiveRecord validations
- **Access structured data** through typed model attributes with full validation support

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
add_column :articles, :json_attributes, :jsonb  # PostgreSQL (default column name)
# or
add_column :articles, :json_attributes, :json   # MySQL (default column name)

# Or if you configure a custom column name:
add_column :articles, :custom_json_column, :jsonb  # PostgreSQL
```

## Configuration

Structify can be configured in an initializer:

```ruby
# config/initializers/structify.rb
Structify.configure do |config|
  # Configure the default JSON container attribute (default: :json_attributes)
  config.default_container_attribute = :custom_json_column
end
```

## Usage

### Define Your Schema

```ruby
class Article < ApplicationRecord
  include Structify::Model

  schema_definition do
    version 1
    name "ArticleExtraction"
    
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

# All data is in the JSON column (default column name: json_attributes)
article.json_attributes  # => The complete JSON
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

## Field Validations

Structify leverages attr_json's integration with ActiveRecord validations to provide comprehensive field-level validation:

```ruby
schema_definition do
  # Basic validations
  field :email, :string, required: true, validations: {
    format: /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
  }
  
  # Length validations
  field :title, :string, validations: {
    length: { minimum: 5, maximum: 200 }
  }
  
  # Numeric validations
  field :age, :integer, validations: {
    numericality: { greater_than_or_equal_to: 18 }
  }
  
  # Custom validations
  field :url, :string, validations: {
    custom: ->(record, field_name) {
      value = record.send(field_name)
      if value && !URI.parse(value).host
        record.errors.add(field_name, "must be a valid URL")
      end
    }
  }
end
```

### Array Validations

Arrays have special validation support:

```ruby
field :tags, :array,
  min_items: 1,
  max_items: 10,
  unique_items: true,
  validations: {
    custom: ->(record, field_name) {
      tags = record.send(field_name) || []
      tags.each do |tag|
        unless tag.is_a?(String) && tag.length >= 2
          record.errors.add(field_name, "items must be strings with 2+ characters")
        end
      end
    }
  }
```

### Nested Model Validations

When using nested models, their validations are automatically applied:

```ruby
class Address
  include AttrJson::Model
  
  attr_json :street, :string
  attr_json :city, :string
  validates :street, :city, presence: true
end

# In your schema:
field :address, Address.to_type, required: true
```

See the [validation guide](docs/validation_guide.md) for comprehensive documentation.

## Chain of Thought Mode

Structify supports a "thinking" mode that automatically requests chain of thought reasoning from the LLM:

```ruby
schema_definition do
  version 1
  thinking true  # Enable chain of thought reasoning
  
  field :title, :string, required: true
  # other fields...
end
```

Chain of thought (COT) reasoning is beneficial because it:
- Adds more context to the extraction process
- Helps the LLM think through problems more systematically
- Improves accuracy for complex extractions
- Makes the reasoning process transparent and explainable
- Reduces hallucinations by forcing step-by-step thinking

This is especially useful when:
- Answers need more detailed information
- Questions require multi-step reasoning
- Extractions involve complex decision-making
- You need to understand how the LLM reached its conclusions

For best results, include instructions for COT in your base system prompt:

```ruby
system_prompt = "Extract structured data from the content. 
For each field, think step by step before determining the value."
```

You can generate effective chain of thought prompts using tools like the [Claude Prompt Designer](https://console.anthropic.com/dashboard).

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

### Accessing the Container Attribute

The JSON container attribute can be accessed directly:

```ruby
# Using the default container attribute :json_attributes
article.json_attributes  # => { "title" => "My Title", "version" => 1, ... }

# If you've configured a custom container attribute
article.custom_json_column  # => { "title" => "My Title", "version" => 1, ... }
```


## Validation & Error Handling

Structify validates all LLM responses and raises specific exceptions for retry logic:

```ruby
begin
  article.update!(llm_response)
rescue Structify::LLMValidationError => e
  RetryExtractionJob.perform_later(article.id, content, e.field_name)
end
```

## Understanding Structify's Role

Structify is designed as a **bridge** between your Rails models and LLM extraction services:

### What Structify Does For You

- ✅ **Define extraction schemas** directly in your ActiveRecord models
- ✅ **Generate compatible JSON schemas** for OpenAI, Anthropic, and other LLM providers
- ✅ **Store and validate** extracted data with automatic error detection
- ✅ **Provide typed access** to extracted fields through your models
- ✅ **Handle schema versioning** and backward compatibility
- ✅ **Raise specific exceptions** for different validation failures to enable retry logic

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