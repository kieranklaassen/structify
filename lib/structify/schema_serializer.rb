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
        # Start with the basic type
        prop = { type: f[:type].to_s }
        
        # Add description if available
        prop[:description] = f[:description] if f[:description]
        
        # Add enum if available
        prop[:enum] = f[:enum] if f[:enum]
        
        # Handle array specific properties
        if f[:type] == :array
          # Add items schema
          prop[:items] = f[:items] if f[:items]
          
          # Add array constraints
          prop[:minItems] = f[:min_items] if f[:min_items]
          prop[:maxItems] = f[:max_items] if f[:max_items]
          prop[:uniqueItems] = f[:unique_items] if f[:unique_items]
        end
        
        # Handle object specific properties
        if f[:type] == :object && f[:properties]
          prop[:properties] = {}
          required_props = []
          
          # Process each property
          f[:properties].each do |prop_name, prop_def|
            prop[:properties][prop_name] = prop_def.dup
            
            # If a property is marked as required, add it to required list and remove from property definition
            if prop_def[:required]
              required_props << prop_name
              prop[:properties][prop_name].delete(:required)
            end
          end
          
          # Add required array if we have required properties
          prop[:required] = required_props unless required_props.empty?
        end
        
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