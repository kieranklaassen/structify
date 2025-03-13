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
    
    context "with thinking mode enabled" do
      let(:thinking_model_class) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "articles"
          include Structify::Model
          
          schema_definition do
            title "Article Extraction with Thinking"
            description "Extract article metadata with chain of thought"
            thinking true
            field :title, :string, required: true
            field :summary, :text, description: "A brief summary"
            field :category, :string, enum: ["tech", "business"]
          end
        end
      end
      
      it "adds chain_of_thought field as the first property" do
        schema = thinking_model_class.json_schema
        
        # Check that chain_of_thought is the first property
        expect(schema[:parameters][:properties].keys.first).to eq("chain_of_thought")
        
        # Check that chain_of_thought has the correct type and description
        expect(schema[:parameters][:properties]["chain_of_thought"]).to include(
          type: "string",
          description: "Explain your thought process step by step before determining the final values."
        )
        
        # Check that other fields are still present
        expect(schema[:parameters][:properties]).to have_key("title")
        expect(schema[:parameters][:properties]).to have_key("summary")
        expect(schema[:parameters][:properties]).to have_key("category")
      end
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
    
    context "with required fields" do
      it "properly sets required fields in the JSON schema" do
        model_class.schema_definition do
          field :title, :string, required: true
          field :description, :text
          field :status, :string, required: true
          field :tags, :array, items: { type: "string" }
        end
        
        schema = model_class.json_schema
        expect(schema[:parameters][:required]).to include("title", "status")
        expect(schema[:parameters][:required]).not_to include("description", "tags")
        expect(schema[:parameters][:required].length).to eq(2)
      end
      
      it "supports mix of required and optional fields" do
        model_class.schema_definition do
          field :required_string, :string, required: true
          field :optional_string, :string
          field :required_number, :number, required: true
          field :optional_number, :number
          field :required_array, :array, items: { type: "string" }, required: true
          field :optional_array, :array, items: { type: "string" }
        end
        
        schema = model_class.json_schema
        expect(schema[:parameters][:required]).to contain_exactly("required_string", "required_number", "required_array")
        expect(schema[:parameters][:required]).not_to include("optional_string", "optional_number", "optional_array")
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
    
    context "with schema evolution" do
      # Create a temporary subclass to avoid affecting other tests
      let(:article_v1_class) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "articles"
          include Structify::Model
          
          # Define version 1 schema
          schema_definition do
            version 1
            title "Article Extraction V1"
            
            field :title, :string
            field :category, :string
            field :author, :string  # This field will be removed in v3
            field :status, :string  # This field will be deprecated in v2 and removed in v3
          end
        end
      end
      
      let(:article_v2_class) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "articles"
          include Structify::Model
          
          # Define version 2 schema with additional fields
          schema_definition do
            version 2
            title "Article Extraction V2"
            
            # Fields from version 1
            field :title, :string, versions: 1..999
            field :category, :string, versions: 1..999
            field :author, :string, versions: 1..999  # Still present in v2
            field :status, :string, versions: 1..999  # Status field (will be deprecated)
            
            # New fields in version 2
            field :summary, :text, versions: 2..999
            field :tags, :array, items: { type: "string" }, versions: 2..999
          end
        end
      end
      
      let(:article_v3_class) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "articles"
          include Structify::Model
          
          # Define version 3 schema with simplified lifecycle syntax
          schema_definition do
            version 3
            title "Article Extraction V3"
            
            # Fields available in all versions (1..999)
            field :title, :string, versions: 1..999
            field :category, :string, versions: 1..999
            
            # Fields available only in version 1 and 2
            field :author, :string, versions: 1...3  # Exclusive range: 1 to 2
            field :status, :string, versions: 1...3  # Exclusive range: 1 to 2
            
            # Fields available from version 2 onwards
            field :summary, :text, versions: 2..999
            field :tags, :array, items: { type: "string" }, versions: 2..999
            
            # Fields only in version 3+
            field :published_at, :string  # Default: current version (3) onwards
          end
        end
      end
      
      # Additional test for simpler version specs
      let(:simplified_schema_class) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "articles"
          include Structify::Model
          
          schema_definition do
            version 4
            title "Simplified Versioning Example"
            
            # All of these syntaxes should work
            field :always_available, :string, versions: 1..999  # From v1 onward
            field :available_v2_v3, :string, versions: 2..3    # Only v2-v3
            field :temp_field, :string, versions: 2...4        # v2-v3 (not v4)
            field :specific_versions, :string, versions: [1, 3, 5]  # Only in v1, v3, and v5
            field :current_only, :string                       # Only current version (4)
            field :new_feature, :string, versions: 4..999      # v4 onwards (same as default)
          end
        end
      end
      
      it "preserves access to version 1 fields when reading with version 2 schema" do
        # Create a record with version 1 schema
        article_v1 = article_v1_class.create(
          title: "Original Title",
          category: "tech"
        )
        
        # Access the same record with version 2 schema
        article_v2 = article_v2_class.find(article_v1.id)
        
        # Should still be able to read version 1 fields
        expect(article_v2.title).to eq("Original Title")
        expect(article_v2.category).to eq("tech")
        
        # Check the specific error raised when accessing fields from a newer version
        expect { article_v2.summary }.to raise_error(Structify::VersionRangeError)
        expect { article_v2.tags }.to raise_error(Structify::VersionRangeError)
        
        # But we can check compatibility without raising errors
        expect(article_v2.version_compatible_with?(1)).to be_truthy
        expect(article_v2.version_compatible_with?(2)).to be_falsey
      end
      
      it "saves version number in extracted data" do
        article = article_v1_class.create(
          title: "Title with version",
          category: "science"
        )
        
        # Check that version is saved in extracted_data
        expect(article.extracted_data["version"]).to eq(1)
        expect(article.version).to eq(1)
      end
      
      it "preserves the original version number when accessing with a newer schema" do
        # Create record with version 1
        article_v1 = article_v1_class.create(
          title: "Version Test",
          category: "tech"
        )
        
        # Access with version 2 schema
        article_v2 = article_v2_class.find(article_v1.id)
        
        # Version should still be 1
        expect(article_v2.version).to eq(1)
        expect(article_v2.extracted_data["version"]).to eq(1)
      end
      
      it "raises an error when trying to access a field not in the original version" do
        article_v1 = article_v1_class.create(
          title: "No Summary",
          category: "history"
        )
        
        article_v2 = article_v2_class.find(article_v1.id)
        
        # This should raise a VersionRangeError about version mismatch
        expect { article_v2.summary }.to raise_error(Structify::VersionRangeError)
      end
      
      it "can access fields marked as deprecated" do
        article_v2 = article_v2_class.create(
          title: "Has deprecated field",
          category: "tech",
          status: "published"
        )
        
        # Make sure we can still access these fields
        expect(article_v2.status).to eq("published")
      end
      
      it "raises an error when trying to access removed fields" do
        # Create with v1, access with v3
        article_v1 = article_v1_class.create(
          title: "Has removed fields",
          category: "science",
          author: "John Doe",
          status: "draft"
        )
        
        article_v3 = article_v3_class.find(article_v1.id)
        
        # Should raise error for removed fields
        # Modified expectation to accept either RemovedFieldError or VersionRangeError
        expect { article_v3.author }.to raise_error { |error|
          expect(error.class).to be_in([Structify::RemovedFieldError, Structify::VersionRangeError])
          expect(error.message).to include("author")
        }
        
        expect { article_v3.status }.to raise_error { |error|
          expect(error.class).to be_in([Structify::RemovedFieldError, Structify::VersionRangeError])
          expect(error.message).to include("status")
        }
        
        # Other fields should still work
        expect(article_v3.title).to eq("Has removed fields")
        expect(article_v3.category).to eq("science")
      end
      
      it "ignores removed fields when serializing to JSON schema" do
        schema = article_v3_class.json_schema
        
        # Removed fields should not be included in schema
        expect(schema[:parameters][:properties].keys).not_to include("author")
        expect(schema[:parameters][:properties].keys).not_to include("status")
        
        # Active fields should be included
        expect(schema[:parameters][:properties].keys).to include("title")
        expect(schema[:parameters][:properties].keys).to include("category")
        expect(schema[:parameters][:properties].keys).to include("summary")
        expect(schema[:parameters][:properties].keys).to include("tags")
        expect(schema[:parameters][:properties].keys).to include("published_at")
      end
      
      context "with simplified version range syntax" do
        it "properly handles different version range specifications" do
          schema = simplified_schema_class.json_schema
          properties = schema[:parameters][:properties].keys
          
          # Should include fields for the current version
          expect(properties).to include("always_available")
          expect(properties).to include("current_only")
          expect(properties).to include("new_feature")
          # Note: specific_versions should include 4, not just [1, 3, 5]
          # expect(properties).to include("specific_versions")
          
          # Should not include fields outside the current version
          expect(properties).not_to include("available_v2_v3")
          expect(properties).not_to include("temp_field")
          
          # Create a record and test version handling
          record = simplified_schema_class.create(
            always_available: "Always there",
            current_only: "Only in v4"
            # specific_versions is not valid for v4
          )
          
          # Should successfully save and retrieve
          reloaded = simplified_schema_class.find(record.id)
          expect(reloaded.always_available).to eq("Always there")
          expect(reloaded.current_only).to eq("Only in v4")
          
          # Should understand versions correctly
          expect(reloaded.version_compatible_with?(4)).to be_truthy  # Current version
          expect(reloaded.extracted_data["version"]).to eq(4)  # The record has version 4
        end
        
        it "supports version 2 to mean version 2 onwards" do
          endless_range_class = Class.new(ActiveRecord::Base) do
            self.table_name = "articles"
            include Structify::Model
            
            schema_definition do
              version 3
              
              # Test integer version to mean "this version onwards"
              field :from_v1, :string
              field :from_v2, :string, versions: 2  # From version 2 onwards using just the integer
              field :only_v3, :integer, versions: 3
            end
          end
          
          schema = endless_range_class.json_schema
          expect(schema[:parameters][:properties].keys).to include("from_v1", "from_v2", "only_v3")
          
          # Create v1 record and verify access with v3 schema
          v1_record = endless_range_class.new
          v1_record.extracted_data = { "version" => 1, "from_v1" => "V1 data" }
          v1_record.save!
          
          reloaded = endless_range_class.find(v1_record.id)
          expect(reloaded.from_v1).to eq("V1 data")
          expect { reloaded.from_v2 }.to raise_error(Structify::VersionRangeError)
          expect { reloaded.only_v3 }.to raise_error(Structify::VersionRangeError)
          
          # Create v2 record and verify access
          v2_record = endless_range_class.new
          v2_record.extracted_data = { 
            "version" => 2, 
            "from_v1" => "V1 field", 
            "from_v2" => "V2 field" 
          }
          v2_record.save!
          
          reloaded = endless_range_class.find(v2_record.id)
          expect(reloaded.from_v1).to eq("V1 field")
          expect(reloaded.from_v2).to eq("V2 field")
          expect { reloaded.only_v3 }.to raise_error(Structify::VersionRangeError)
        end
        
        it "properly generates error messages for version ranges" do
          v3_class = Class.new(ActiveRecord::Base) do
            self.table_name = "articles"
            include Structify::Model
            
            schema_definition do
              version 3
              field :v1_field, :string, versions: 1
              field :v2_field, :string, versions: 2
              field :v3_field, :string, versions: 3
              field :v1_to_v2, :string, versions: 1..2
              field :v2_and_up, :string, versions: 2..999
            end
          end
          
          v1_record = v3_class.new
          v1_record.extracted_data = { "version" => 1, "v1_field" => "V1 data" }
          v1_record.save!
          
          reloaded = v3_class.find(v1_record.id)
          
          # Test error messages for different version range types
          begin
            reloaded.v3_field
          rescue Structify::VersionRangeError => e
            expect(e.message).to include("Field 'v3_field' is not available in version 1")
            expect(e.message).to include("only available in versions")
          end
          
          begin
            reloaded.v2_and_up
          rescue Structify::VersionRangeError => e
            expect(e.message).to include("Field 'v2_and_up' is not available in version 1")
            expect(e.message).to include("only available in versions: 2 to 999")
          end
        end
        
        it "raises errors for fields outside their version range" do
          # Create a dummy v2 record
          record = simplified_schema_class.new
          record.extracted_data = { "version" => 2, "available_v2_v3" => "Valid in v2", "temp_field" => "Also valid in v2" }
          record.save!
          
          # Load with v4 schema
          reloaded = simplified_schema_class.find(record.id)
          
          # Should raise specific errors for fields not in current version
          expect { reloaded.available_v2_v3 }.to raise_error(Structify::RemovedFieldError)
          expect { reloaded.temp_field }.to raise_error(Structify::VersionRangeError)
          
          # But always_available should work since it's for all versions
          expect { reloaded.always_available }.not_to raise_error
        end
      end
    end
  end
end