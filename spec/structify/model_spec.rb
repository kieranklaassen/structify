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

  describe "field definitions" do
    it "creates attr_json attributes for each field" do
      model_class.schema_definition do
        field :title, :string
        field :summary, :text
      end

      instance = model_class.new
      instance.title = "Test Title"
      instance.summary = "Test Summary"

      expect(instance.title).to eq("Test Title")
      expect(instance.summary).to eq("Test Summary")
    end

    it "handles required fields in the schema" do
      model_class.schema_definition do
        field :title, :string, required: true
        field :summary, :text, required: false
      end

      schema = model_class.json_schema
      expect(schema[:parameters][:required]).to eq(["title"])
      expect(schema[:parameters][:properties]["title"]).to eq(type: "string")
    end

    it "handles field descriptions" do
      model_class.schema_definition do
        field :title, :string, description: "The article title"
      end

      schema = model_class.json_schema
      expect(schema[:parameters][:properties]["title"][:description]).to eq("The article title")
    end

    it "handles enums" do
      model_class.schema_definition do
        field :category, :string, enum: ["tech", "business"]
      end

      schema = model_class.json_schema
      expect(schema[:parameters][:properties]["category"][:enum]).to eq(["tech", "business"])
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