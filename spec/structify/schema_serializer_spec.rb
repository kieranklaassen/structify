# frozen_string_literal: true

require "spec_helper"

RSpec.describe Structify::SchemaSerializer do
  let(:model_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "articles"
      include Structify::Model
    end
  end

  let(:schema_builder) do
    builder = Structify::SchemaBuilder.new(model_class)
    builder.name("TestSchema")
    builder.description("Test Description")
    builder.field(:title, :string, required: true, description: "The title")
    builder.field(:category, :string, enum: ["tech", "business"])
    builder
  end

  let(:serializer) { described_class.new(schema_builder) }

  describe "#to_json_schema" do
    it "generates a valid JSON schema" do
      schema = serializer.to_json_schema

      expect(schema[:name]).to eq("TestSchema")
      expect(schema[:description]).to eq("Test Description")
      expect(schema[:parameters]).to be_a(Hash)
      expect(schema[:parameters][:required]).to eq(["title"])
      expect(schema[:parameters][:properties]["title"]).to include(type: "string", description: "The title")
      expect(schema[:parameters][:properties]["category"][:enum]).to eq(["tech", "business"])
    end

    it "handles fields without descriptions or enums" do
      builder = Structify::SchemaBuilder.new(model_class)
      builder.field(:simple_field, :string)
      serializer = described_class.new(builder)

      schema = serializer.to_json_schema
      expect(schema[:parameters][:properties]["simple_field"]).to eq(type: "string")
    end
    
    it "includes chain_of_thought field as the first property when thinking mode is enabled" do
      builder = Structify::SchemaBuilder.new(model_class)
      # We need to set the thinking mode flag on the builder
      # This will be implemented in the SchemaBuilder class
      builder.instance_variable_set(:@thinking_enabled, true)
      serializer = described_class.new(builder)

      schema = serializer.to_json_schema
      
      # Check that chain_of_thought exists with correct properties
      expect(schema[:parameters][:properties]["chain_of_thought"]).to include(
        type: "string",
        description: "Explain your thought process step by step before determining the final values."
      )
      
      # Check that chain_of_thought is the first property
      expect(schema[:parameters][:properties].keys.first).to eq("chain_of_thought")
    end

    it "does not include chain_of_thought field when thinking mode is not enabled" do
      builder = Structify::SchemaBuilder.new(model_class)
      # Default value should be false
      serializer = described_class.new(builder)

      schema = serializer.to_json_schema
      expect(schema[:parameters][:properties]).not_to have_key("chain_of_thought")
    end
    
    it "only includes fields for the current schema version" do
      builder = Structify::SchemaBuilder.new(model_class)
      builder.version(2) # Set current version to 2
      
      # v1 fields
      builder.field(:v1_field1, :string, versions: 1)
      builder.field(:v1_field2, :string, versions: 1)
      
      # v2 fields
      builder.field(:v2_field1, :string, versions: 2)
      builder.field(:v2_field2, :string, versions: 2)
      
      # Common field for both versions
      builder.field(:common_field, :string)
      
      serializer = described_class.new(builder)
      schema = serializer.to_json_schema
      
      # Should include v2 fields and common fields
      expect(schema[:parameters][:properties]).to have_key("v2_field1")
      expect(schema[:parameters][:properties]).to have_key("v2_field2")
      expect(schema[:parameters][:properties]).to have_key("common_field")
      
      # Should NOT include v1 fields
      expect(schema[:parameters][:properties]).not_to have_key("v1_field1")
      expect(schema[:parameters][:properties]).not_to have_key("v1_field2")
    end
  end
end