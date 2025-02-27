# frozen_string_literal: true

module Structify
  # Handles serialization of schema definitions to different formats
  class SchemaSerializer
    # @return [Structify::SchemaBuilder] The schema builder to serialize
    attr_reader :schema_builder

    # Initialize a new SchemaSerializer
    #
    # @param schema_builder [Structify::SchemaBuilder] The schema builder to serialize
    def initialize(schema_builder)
      @schema_builder = schema_builder
    end

    # Generate the JSON schema representation
    #
    # @return [Hash] The JSON schema
    def to_json_schema
      fields = schema_builder.fields
      required_fields = fields.select { |f| f[:required] }.map { |f| f[:name].to_s }
      properties_hash = fields.each_with_object({}) do |f, hash|
        prop = { type: f[:type].to_s }
        prop[:description] = f[:description] if f[:description]
        prop[:enum] = f[:enum] if f[:enum]
        hash[f[:name].to_s] = prop
      end

      {
        name: schema_builder.title_str,
        description: schema_builder.description_str,
        parameters: {
          type: "object",
          required: required_fields,
          properties: properties_hash
        }
      }
    end
  end
end