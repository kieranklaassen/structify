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
        t.json :json_attributes
        t.timestamps
      end
    end
  end

  describe ".schema_definition" do
    it "allows defining a schema with ruby_llm-schema DSL" do
      model_class.schema_definition do
        name "ArticleExtraction"
        description "Extract article metadata"

        string :title
        string :summary, required: false
        string :category, enum: ["tech", "business"]
      end

      expect(model_class.structify_schema).to be < RubyLLM::Schema
    end

    it "allows various schema name formats" do
      # Valid names - ruby_llm-schema handles name validation
      expect {
        model_class.schema_definition do
          name "ValidName"
        end
      }.not_to raise_error

      expect {
        model_class.schema_definition do
          name "valid_name_with_underscores"
        end
      }.not_to raise_error

      expect {
        model_class.schema_definition do
          name "valid-name-with-hyphens"
        end
      }.not_to raise_error
    end
  end

  describe ".json_schema" do
    before do
      model_class.schema_definition do
        name "ArticleExtraction"
        description "Extract article metadata"

        string :title
        string :summary, required: false, description: "A brief summary"
        string :category, enum: ["tech", "business"]
      end
    end

    it "generates a valid JSON schema" do
      schema = model_class.json_schema

      expect(schema[:name]).to eq("ArticleExtraction")
      expect(schema[:description]).to eq("Extract article metadata")
      expect(schema[:properties]).to be_a(Hash)
      expect(schema[:properties][:title]).to be_a(Hash)
      expect(schema[:properties][:title][:type]).to eq("string")
    end

    it "includes required fields" do
      schema = model_class.json_schema

      # In ruby_llm-schema, fields are required by default unless marked required: false
      required = schema[:required]
      expect(required).to include("title")
      expect(required).to include("category")
      # summary has required: false so should not be in required
      expect(required).not_to include("summary")
    end

    it "includes enum values" do
      schema = model_class.json_schema

      expect(schema[:properties][:category][:enum]).to eq(["tech", "business"])
    end
  end

  describe "different data types and field options" do
    it "supports string type" do
      model_class.schema_definition do
        string :title
      end

      schema = model_class.json_schema
      expect(schema[:properties][:title][:type]).to eq("string")
    end

    it "supports integer type" do
      model_class.schema_definition do
        integer :count
      end

      schema = model_class.json_schema
      expect(schema[:properties][:count][:type]).to eq("integer")
    end

    it "supports number type" do
      model_class.schema_definition do
        number :price
      end

      schema = model_class.json_schema
      expect(schema[:properties][:price][:type]).to eq("number")
    end

    it "supports boolean type" do
      model_class.schema_definition do
        boolean :published
      end

      schema = model_class.json_schema
      expect(schema[:properties][:published][:type]).to eq("boolean")
    end

    it "supports array type with of option" do
      model_class.schema_definition do
        array :tags, of: :string
      end

      schema = model_class.json_schema
      expect(schema[:properties][:tags][:type]).to eq("array")
      expect(schema[:properties][:tags][:items][:type]).to eq("string")
    end

    it "supports array type with constraints" do
      model_class.schema_definition do
        array :tags, of: :string, min_items: 1, max_items: 5
      end

      schema = model_class.json_schema
      expect(schema[:properties][:tags][:minItems]).to eq(1)
      expect(schema[:properties][:tags][:maxItems]).to eq(5)
    end

    it "supports object type with properties" do
      model_class.schema_definition do
        object :metadata do
          string :author
          integer :views
        end
      end

      schema = model_class.json_schema
      expect(schema[:properties][:metadata][:type]).to eq("object")
      expect(schema[:properties][:metadata][:properties][:author][:type]).to eq("string")
      expect(schema[:properties][:metadata][:properties][:views][:type]).to eq("integer")
    end

    it "supports nested object types" do
      model_class.schema_definition do
        object :user_data do
          string :name
          object :contact do
            string :email
            string :phone, required: false
          end
        end
      end

      schema = model_class.json_schema
      expect(schema[:properties][:user_data][:properties][:contact][:properties][:email][:type]).to eq("string")
    end
  end

  describe "attr_json integration" do
    before do
      model_class.schema_definition do
        string :title
        integer :count, required: false
        boolean :published, required: false
        array :tags, of: :string, required: false
        object :metadata, required: false do
          string :author, required: false
        end
      end
    end

    it "creates attr_json fields for each schema property" do
      instance = model_class.new

      # Should respond to all defined fields
      expect(instance).to respond_to(:title)
      expect(instance).to respond_to(:title=)
      expect(instance).to respond_to(:count)
      expect(instance).to respond_to(:published)
      expect(instance).to respond_to(:tags)
      expect(instance).to respond_to(:metadata)
    end

    it "allows setting and getting values" do
      instance = model_class.new

      instance.title = "Test Article"
      instance.count = 42
      instance.published = true
      instance.tags = ["ruby", "rails"]
      instance.metadata = {"author" => "John"}

      expect(instance.title).to eq("Test Article")
      expect(instance.count).to eq(42)
      expect(instance.published).to eq(true)
      expect(instance.tags).to eq(["ruby", "rails"])
      expect(instance.metadata).to eq({"author" => "John"})
    end

    it "persists data to the database" do
      instance = model_class.new
      instance.title = "Test Article"
      instance.count = 42
      instance.save!

      reloaded = model_class.find(instance.id)
      expect(reloaded.title).to eq("Test Article")
      expect(reloaded.count).to eq(42)
    end
  end

  describe "change tracking" do
    before do
      model_class.schema_definition do
        string :title
      end
    end

    it "tracks changes to extracted data with default container attribute" do
      instance = model_class.create!(title: "Original")

      instance.title = "Updated"
      instance.save!

      expect(instance.saved_change_to_extracted_data?).to be true
    end
  end

  describe "with custom container attribute" do
    let(:custom_model_class) do
      # Create a fresh class for custom container
      Class.new(ActiveRecord::Base) do
        self.table_name = "articles"
        include Structify::Model

        # Use content as the container (assuming it's a json column)
        attr_json_config(default_container_attribute: :json_attributes)
      end
    end

    before do
      custom_model_class.schema_definition do
        string :title
      end
    end

    it "respects the custom container attribute" do
      instance = custom_model_class.new
      instance.title = "Custom"

      expect(instance.title).to eq("Custom")
    end
  end

  describe "with enum for different types" do
    it "handles string enum" do
      model_class.schema_definition do
        string :status, enum: ["active", "inactive", "pending"]
      end

      schema = model_class.json_schema
      expect(schema[:properties][:status][:enum]).to eq(["active", "inactive", "pending"])
    end
  end

  describe "with required fields" do
    before do
      model_class.schema_definition do
        string :required_field
        string :optional_field, required: false
      end
    end

    it "properly sets required fields in the JSON schema" do
      schema = model_class.json_schema

      expect(schema[:required]).to include("required_field")
      expect(schema[:required]).not_to include("optional_field")
    end
  end

  describe "schema caching" do
    before do
      model_class.schema_definition do
        name "CachingTest"
        string :title
        integer :count, required: false
      end
    end

    it "caches json_schema between calls" do
      schema1 = model_class.cached_json_schema
      schema2 = model_class.cached_json_schema

      expect(schema1).to be(schema2) # Same object
    end

    it "caches properties between calls" do
      props1 = model_class.cached_properties
      props2 = model_class.cached_properties

      expect(props1).to be(props2) # Same object
    end

    it "returns required fields as strings not symbols" do
      required = model_class.cached_required_fields

      expect(required).to all(be_a(String))
      expect(required).to include("title")
    end
  end

  describe "without schema definition" do
    let(:bare_model_class) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "articles"
        include Structify::Model
        # No schema_definition called
      end
    end

    it "returns nil for json_schema" do
      expect(bare_model_class.json_schema).to be_nil
    end

    it "returns empty hash for cached_properties" do
      expect(bare_model_class.cached_properties).to eq({})
    end

    it "returns empty array for cached_required_fields" do
      expect(bare_model_class.cached_required_fields).to eq([])
    end

    it "does not raise on save" do
      instance = bare_model_class.new
      expect { instance.save! }.not_to raise_error
    end
  end

  describe "with falsy but valid values" do
    before do
      model_class.schema_definition do
        name "FalsyValues"
        boolean :active, required: false
        integer :count, required: false
        string :title, required: false
      end
    end

    it "accepts false for boolean fields" do
      instance = model_class.new(active: false)
      expect { instance.save! }.not_to raise_error
      expect(instance.active).to eq(false)
    end

    it "accepts 0 for integer fields" do
      instance = model_class.new(count: 0)
      expect { instance.save! }.not_to raise_error
      expect(instance.count).to eq(0)
    end

    it "accepts empty string when field is optional" do
      instance = model_class.new(title: "")
      # Empty string is allowed for optional fields
      expect { instance.save! }.not_to raise_error
    end
  end

  describe "versioning" do
    let(:versioned_model_class) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "articles"
        include Structify::Model
      end
    end

    before do
      versioned_model_class.schema_definition do
        name "VersionedSchema"
        version 2

        string :title
        string :summary, required: false
      end
    end

    it "sets the schema version via extraction_version" do
      expect(versioned_model_class.extraction_version).to eq(2)
    end

    it "creates a version attr_json field with default" do
      instance = versioned_model_class.new
      expect(instance).to respond_to(:version)
      expect(instance.version).to eq(2)
    end

    it "stores version in the extracted data" do
      instance = versioned_model_class.new(title: "Test")
      instance.save!

      expect(instance.stored_version).to eq(2)
    end

    it "returns stored_version from record data" do
      instance = versioned_model_class.new(title: "Test")
      instance.save!

      # Manually set a different version in the container
      instance.json_attributes["version"] = 1
      expect(instance.stored_version).to eq(1)
    end

    it "checks version compatibility" do
      instance = versioned_model_class.new(title: "Test", version: 2)
      instance.save!

      expect(instance.version_compatible_with?(1)).to be true
      expect(instance.version_compatible_with?(2)).to be true
      expect(instance.version_compatible_with?(3)).to be false
    end

    it "defaults to version 1 when no version in schema" do
      bare_model = Class.new(ActiveRecord::Base) do
        self.table_name = "articles"
        include Structify::Model
      end

      bare_model.schema_definition do
        name "UnversionedSchema"
        string :title
      end

      expect(bare_model.extraction_version).to eq(1)
    end

    it "generates a schema_checksum for change detection" do
      expect(versioned_model_class.schema_checksum).to be_a(String)
      expect(versioned_model_class.schema_checksum.length).to eq(32) # MD5 hex length
    end

    it "returns different checksums for different schemas" do
      other_model = Class.new(ActiveRecord::Base) do
        self.table_name = "articles"
        include Structify::Model
      end

      other_model.schema_definition do
        name "OtherSchema"
        string :different_field
      end

      expect(versioned_model_class.schema_checksum).not_to eq(other_model.schema_checksum)
    end
  end
end
