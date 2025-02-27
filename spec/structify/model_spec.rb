# frozen_string_literal: true

require "spec_helper"

RSpec.describe Structify::Model do
  # Create a test model class that includes our module
  let(:model_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "articles"
      include Structify::Model
    end
  end

  # Set up our test database
  before(:all) do
    ActiveRecord::Schema.define do
      create_table :articles, force: true do |t|
        t.string :title
        t.text :content
        t.json :extracted_data
        t.timestamps
      end
    end
  end

  describe ".schema_definition" do
    it "allows defining a schema with all available options" do
      model_class.schema_definition do
        title "Article Extraction"
        description "Extract article metadata"
        version 2

        field :title, :string, required: true
        field :summary, :text, description: "A brief summary"
        field :category, :string, enum: ["tech", "business"]
      end

      expect(model_class.schema_builder).to be_a(Structify::SchemaBuilder)
      expect(model_class.extraction_version).to eq(2)
    end
  end

  describe ".json_schema" do
    before do
      model_class.schema_definition do
        title "Article Extraction"
        description "Extract article metadata"
        field :title, :string, required: true
        field :summary, :text, description: "A brief summary"
        field :category, :string, enum: ["tech", "business"]
      end
    end

    it "generates a valid JSON schema" do
      schema = model_class.json_schema

      expect(schema[:name]).to eq("Article Extraction")
      expect(schema[:description]).to eq("Extract article metadata")
      expect(schema[:parameters]).to be_a(Hash)
      expect(schema[:parameters][:required]).to eq(["title"])
      expect(schema[:parameters][:properties]["title"]).to eq(type: "string")
      expect(schema[:parameters][:properties]["category"][:enum]).to eq(["tech", "business"])
    end
  end
  
  describe "different data types and field options" do
    it "supports string type" do
      model_class.schema_definition do
        field :title, :string
      end
      
      instance = model_class.new(title: "Test Title")
      expect(instance.title).to eq("Test Title")
      
      schema = model_class.json_schema
      expect(schema[:parameters][:properties]["title"][:type]).to eq("string")
    end
    
    it "supports integer type" do
      model_class.schema_definition do
        field :count, :integer
      end
      
      instance = model_class.new(count: 42)
      expect(instance.count).to eq(42)
      
      schema = model_class.json_schema
      expect(schema[:parameters][:properties]["count"][:type]).to eq("integer")
    end
    
    it "supports number type" do
      model_class.schema_definition do
        field :price, :number
      end
      
      instance = model_class.new(price: 99)
      expect(instance.price).to eq(99)
      
      schema = model_class.json_schema
      expect(schema[:parameters][:properties]["price"][:type]).to eq("number")
    end
    
    it "supports boolean type" do
      model_class.schema_definition do
        field :published, :boolean
      end
      
      instance = model_class.new(published: true)
      expect(instance.published).to eq(true)
      
      schema = model_class.json_schema
      expect(schema[:parameters][:properties]["published"][:type]).to eq("boolean")
    end
    
    it "supports array type with items" do
      model_class.schema_definition do
        field :tags, :array, items: { type: "string" }
      end
      
      instance = model_class.new(tags: ["ruby", "rails"])
      expect(instance.tags).to eq(["ruby", "rails"])
      
      schema = model_class.json_schema
      expect(schema[:parameters][:properties]["tags"][:type]).to eq("array")
      expect(schema[:parameters][:properties]["tags"][:items]).to eq({ type: "string" })
    end
    
    it "supports array type with constraints" do
      model_class.schema_definition do
        field :tags, :array, 
          items: { type: "string" },
          min_items: 1,
          max_items: 5,
          unique_items: true
      end
      
      schema = model_class.json_schema
      expect(schema[:parameters][:properties]["tags"][:minItems]).to eq(1)
      expect(schema[:parameters][:properties]["tags"][:maxItems]).to eq(5)
      expect(schema[:parameters][:properties]["tags"][:uniqueItems]).to eq(true)
    end
    
    it "supports object type with properties" do
      model_class.schema_definition do
        field :metadata, :object, properties: {
          "author" => { type: "string" },
          "views" => { type: "integer" }
        }
      end
      
      instance = model_class.new(metadata: { "author" => "John", "views" => 100 })
      expect(instance.metadata).to eq({ "author" => "John", "views" => 100 })
      
      schema = model_class.json_schema
      expect(schema[:parameters][:properties]["metadata"][:type]).to eq("object")
      expect(schema[:parameters][:properties]["metadata"][:properties]).to eq({
        "author" => { type: "string" },
        "views" => { type: "integer" }
      })
    end
    
    it "supports complex nested object types" do
      model_class.schema_definition do
        field :user_data, :object, properties: {
          "profile" => { 
            type: "object", 
            properties: {
              "name" => { type: "string" },
              "contact" => {
                type: "object",
                properties: {
                  "email" => { type: "string" },
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
      end
      
      # Test complex nested object storage and retrieval
      complex_data = {
        "profile" => {
          "name" => "Jane Smith",
          "contact" => {
            "email" => "jane@example.com",
            "phone" => "555-1234"
          }
        },
        "preferences" => {
          "theme" => "dark",
          "notifications" => true
        }
      }
      
      instance = model_class.new(user_data: complex_data)
      expect(instance.user_data).to eq(complex_data)
      
      # Access nested values
      expect(instance.user_data["profile"]["name"]).to eq("Jane Smith")
      expect(instance.user_data["profile"]["contact"]["email"]).to eq("jane@example.com")
      expect(instance.user_data["preferences"]["theme"]).to eq("dark")
      
      # Verify schema contains nested structure
      schema = model_class.json_schema
      expect(schema[:parameters][:properties]["user_data"][:type]).to eq("object")
      expect(schema[:parameters][:properties]["user_data"][:properties]["profile"][:type]).to eq("object")
      expect(schema[:parameters][:properties]["user_data"][:properties]["profile"][:properties]["contact"][:properties]["email"][:type]).to eq("string")
    end
    
    it "handles objects with required properties" do
      model_class.schema_definition do
        field :contact, :object, properties: {
          "name" => { type: "string", required: true },
          "email" => { type: "string", required: true },
          "address" => { type: "string" }
        }
      end
      
      instance = model_class.new(contact: { 
        "name" => "Alice",
        "email" => "alice@example.com",
        "address" => "123 Main St"
      })
      
      expect(instance.contact["name"]).to eq("Alice")
      expect(instance.contact["email"]).to eq("alice@example.com")
      
      # Update a value in the object
      instance.contact["name"] = "Alice Smith"
      expect(instance.contact["name"]).to eq("Alice Smith")
      
      # Add a new key to the object
      instance.contact["phone"] = "555-5678"
      expect(instance.contact["phone"]).to eq("555-5678")
      
      # Verify schema has required properties correctly defined
      schema = model_class.json_schema
      expect(schema[:parameters][:properties]["contact"][:required]).to include("name", "email")
      expect(schema[:parameters][:properties]["contact"][:required].length).to eq(2)
      expect(schema[:parameters][:properties]["contact"][:properties]["name"][:required]).to be_nil
    end
    
    it "handles object with array of objects" do
      model_class.schema_definition do
        field :document, :object, properties: {
          "title" => { type: "string" },
          "sections" => { 
            type: "array",
            items: {
              type: "object",
              properties: {
                "heading" => { type: "string" },
                "content" => { type: "string" }
              }
            }
          }
        }
      end
      
      doc_data = {
        "title" => "Annual Report",
        "sections" => [
          { "heading" => "Introduction", "content" => "This report covers..." },
          { "heading" => "Financial Results", "content" => "Revenue increased by..." }
        ]
      }
      
      instance = model_class.new(document: doc_data)
      
      # Test round-trip serialization
      expect(instance.document).to eq(doc_data)
      
      # Access nested array of objects
      expect(instance.document["sections"].length).to eq(2)
      expect(instance.document["sections"][0]["heading"]).to eq("Introduction")
      expect(instance.document["sections"][1]["content"]).to eq("Revenue increased by...")
      
      # Verify schema structure
      schema = model_class.json_schema
      expect(schema[:parameters][:properties]["document"][:properties]["sections"][:type]).to eq("array")
      expect(schema[:parameters][:properties]["document"][:properties]["sections"][:items][:type]).to eq("object")
    end
  
    context "with enum for different types" do
      it "handles string enum" do
        model_class.schema_definition do
          field :color, :string, enum: ["red", "green", "blue"]
        end
        
        schema = model_class.json_schema
        expect(schema[:parameters][:properties]["color"][:enum]).to eq(["red", "green", "blue"])
      end
      
      it "handles integer enum" do
        model_class.schema_definition do
          field :priority, :integer, enum: [1, 2, 3]
        end
        
        schema = model_class.json_schema
        expect(schema[:parameters][:properties]["priority"][:enum]).to eq([1, 2, 3])
      end
      
      it "handles number enum" do
        model_class.schema_definition do
          field :score, :number, enum: [1.5, 2.5, 3.5]
        end
        
        schema = model_class.json_schema
        expect(schema[:parameters][:properties]["score"][:enum]).to eq([1.5, 2.5, 3.5])
      end
      
      it "handles boolean enum" do
        model_class.schema_definition do
          field :flag, :boolean, enum: [true, false]
        end
        
        schema = model_class.json_schema
        expect(schema[:parameters][:properties]["flag"][:enum]).to eq([true, false])
      end
    end
  end

  describe "versioning" do
    it "sets and gets the version number" do
      model_class.schema_definition do
        version 2
      end

      expect(model_class.extraction_version).to eq(2)
    end

    it "defaults to version 1 if not specified" do
      model_class.schema_definition do
        title "Test"
      end

      expect(model_class.extraction_version).to eq(1)
    end
  end
end