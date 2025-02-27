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
    builder.title("Test Schema")
    builder.description("Test Description")
    builder.field(:title, :string, required: true, description: "The title")
    builder.field(:category, :string, enum: ["tech", "business"])
    builder
  end

  let(:serializer) { described_class.new(schema_builder) }

  describe "#to_json_schema" do
    it "generates a valid JSON schema" do
      schema = serializer.to_json_schema

      expect(schema[:name]).to eq("Test Schema")
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
  end
end