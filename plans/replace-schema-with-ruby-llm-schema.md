# Plan: Replace Custom Schema Definitions with ruby_llm-schema

## Overview

Make `schema_definition` a thin wrapper around [ruby_llm-schema](https://github.com/danielfriis/ruby_llm-schema), giving users direct access to the full ruby_llm-schema DSL while Structify handles ActiveRecord integration and validation.

## Problem Statement / Motivation

Structify currently maintains its own schema definition DSL with:
- `SchemaBuilder` (387 lines in `lib/structify/model.rb`)
- `SchemaSerializer` (197 lines in `lib/structify/schema_serializer.rb`)

**Why change?**
1. **Reduce maintenance burden** - Delete ~500 lines of schema code
2. **Gain features** - `any_of` union types, recursive schemas, `define`/`reference`, format constraints
3. **Ecosystem alignment** - ruby_llm-schema is designed for RubyLLM integration
4. **Simpler codebase** - Focus Structify on its unique value: ActiveRecord integration + validation

## Proposed Solution

Make `schema_definition` a thin wrapper that passes through to `RubyLLM::Schema`.

**⚠️ BREAKING CHANGE**: DSL changes from `field :title, :string` to `string :title`

### Before (Current DSL)

```ruby
class Article < ApplicationRecord
  include Structify::Model

  schema_definition do
    name "ArticleExtraction"
    field :title, :string, required: true
    field :summary, :text
    field :tags, :array, items: { type: "string" }
    field :author, :object, properties: {
      "name" => { type: "string" },
      "email" => { type: "string" }
    }
  end
end
```

### After (ruby_llm-schema DSL)

```ruby
class Article < ApplicationRecord
  include Structify::Model

  schema_definition do
    name "ArticleExtraction"

    string :title
    string :summary, required: false
    array :tags, of: :string, min_items: 1

    object :author do
      string :name
      string :email, format: "email", required: false
    end

    # New capabilities:
    any_of :status do
      string enum: ["draft", "published"]
      null
    end

    define :location do
      string :city
      string :country
    end

    array :offices, of: :location
  end
end
```

### What Changes

| Component | Current | After |
|-----------|---------|-------|
| DSL | `field :name, :type` | `string :name`, `integer :age`, etc. |
| Schema class | `SchemaBuilder` | `RubyLLM::Schema` subclass |
| JSON Output | `SchemaSerializer` | `RubyLLM::Schema#to_json_schema` |
| Nested Objects | Hash syntax | Block syntax |
| Delete | `SchemaSerializer` | - |

### What Stays The Same

| Component | Behavior |
|-----------|----------|
| `schema_definition` block | Entry point (contents change) |
| `Model.json_schema` | Returns JSON schema |
| AttrJson integration | Automatic `attr_json` field creation |
| FieldValidation | Always-on validation |
| Error hierarchy | Same custom exceptions |

## Technical Approach

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     User Code                                │
│   schema_definition do                                       │
│     string :title          # ruby_llm-schema DSL directly   │
│     array :tags, of: :string                                │
│   end                                                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              Structify::Model (thin wrapper)                 │
│   - Creates RubyLLM::Schema subclass                        │
│   - Evals block in schema context                           │
│   - Creates attr_json fields from schema properties         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    RubyLLM::Schema                           │
│   - Handles all schema definition                           │
│   - Provides to_json_schema                                 │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              FieldValidation (adapted)                       │
│   - Reads from RubyLLM::Schema properties                   │
│   - Validates LLM responses                                 │
└─────────────────────────────────────────────────────────────┘
```

## Acceptance Criteria

### Functional Requirements
- [ ] `schema_definition` block accepts ruby_llm-schema DSL
- [ ] `Model.json_schema` returns JSON schema via `RubyLLM::Schema#to_json_schema`
- [ ] All ruby_llm-schema types work: `string`, `integer`, `number`, `boolean`, `array`, `object`, `any_of`
- [ ] AttrJson fields created automatically from schema properties
- [ ] FieldValidation validates against schema properties

### Non-Functional Requirements
- [ ] Delete `SchemaSerializer` entirely
- [ ] Simplify `SchemaBuilder` to thin wrapper
- [ ] Bump major version (breaking change)

### Features to Remove
- [ ] Schema versioning (`version`, `versions:` ranges) - simplify, not needed
- [ ] `thinking true` mode - users can add `string :chain_of_thought` manually

## Implementation Steps

1. Add `ruby_llm-schema` gem dependency
2. Rewrite `schema_definition` to create `RubyLLM::Schema` subclass
3. Create `attr_json` fields by reading schema properties
4. Replace `json_schema` method to call `schema.to_json_schema`
5. Update `FieldValidation` to read from `RubyLLM::Schema` properties
6. Delete `SchemaSerializer`
7. Delete versioning code from `SchemaBuilder`
8. Update all tests
9. Update README
10. Bump to v1.0.0

## Dependencies

```ruby
# Gemfile
gem "ruby_llm-schema", "~> 0.2"
```

## References

- ruby_llm-schema: https://github.com/danielfriis/ruby_llm-schema
- Current SchemaBuilder: `lib/structify/model.rb:126-512`
- Current SchemaSerializer: `lib/structify/schema_serializer.rb:1-197`

---

## MVP Implementation

### lib/structify/model.rb (simplified)

```ruby
# frozen_string_literal: true

require "ruby_llm/schema"

module Structify
  module Model
    extend ActiveSupport::Concern

    included do
      include AttrJson::Record
      include Structify::FieldValidation

      class_attribute :structify_schema, instance_writer: false
    end

    class_methods do
      def schema_definition(&block)
        # Create a RubyLLM::Schema subclass dynamically
        schema_class = Class.new(RubyLLM::Schema)
        schema_class.class_eval(&block) if block_given?

        self.structify_schema = schema_class

        # Create attr_json fields from schema properties
        schema_instance = schema_class.new
        create_attr_json_fields_from_schema(schema_instance)
      end

      def json_schema
        structify_schema.new.to_json_schema
      end

      private

      def create_attr_json_fields_from_schema(schema)
        schema.to_json_schema[:properties]&.each do |name, definition|
          type = map_json_schema_type(definition[:type])
          attr_json name, type
        end
      end

      def map_json_schema_type(json_type)
        case json_type
        when "string" then :string
        when "integer" then :integer
        when "number" then :float
        when "boolean" then :boolean
        when "array", "object" then :json
        else :string
        end
      end
    end
  end
end
```

### Example Usage

```ruby
class Article < ApplicationRecord
  include Structify::Model

  schema_definition do
    name "ArticleExtraction"
    description "Extract article metadata"

    string :title, description: "Article title"
    string :summary, required: false
    integer :word_count, minimum: 0

    array :tags, of: :string, min_items: 1

    object :author do
      string :name
      string :email, format: "email", required: false
    end

    any_of :status do
      string enum: ["draft", "published"]
      null
    end
  end
end

# Usage
Article.json_schema
# => { name: "ArticleExtraction", type: "object", properties: {...}, ... }

article = Article.new
article.title = "Hello World"
article.author = { "name" => "John", "email" => "john@example.com" }
article.save!
```
