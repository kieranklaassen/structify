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
      # Get current schema version
      current_version = schema_builder.version_number
      
      # Get fields that are applicable to the current schema version
      fields = schema_builder.fields.select do |f|
        # Check if the field has a version_range
        if f[:version_range]
          version_in_range?(current_version, f[:version_range])
        # Legacy check for removed_in
        elsif f[:removed_in]
          f[:removed_in] > current_version
        else
          true
        end
      end
      
      # Get required fields (excluding fields not in the current version)
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
        
        # Add version info to description only if requested by environment variable
        # This allows for backward compatibility with existing tests
        if ENV["STRUCTIFY_SHOW_VERSION_INFO"] && f[:version_range] && prop[:description]
          version_info = format_version_range(f[:version_range])
          prop[:description] = "#{prop[:description]} (Available in versions: #{version_info})"
        elsif ENV["STRUCTIFY_SHOW_VERSION_INFO"] && f[:version_range]
          prop[:description] = "Available in versions: #{format_version_range(f[:version_range])}"
        end
        
        # Legacy: Add a deprecation notice to description
        if f[:deprecated_in] && f[:deprecated_in] <= current_version
          deprecation_note = "Deprecated in v#{f[:deprecated_in]}. "
          prop[:description] = if prop[:description]
                                "#{deprecation_note}#{prop[:description]}"
                              else
                                deprecation_note
                              end
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
    
    private
    
    # Check if a version is within a given range/array of versions
    #
    # @param version [Integer] The version to check
    # @param range [Range, Array, Integer] The range, array, or single version to check against
    # @return [Boolean] Whether the version is within the range
    def version_in_range?(version, range)
      case range
      when Range
        range.cover?(version)
      when Array
        range.include?(version)
      else
        version == range
      end
    end
    
    # Format a version range for display in error messages
    #
    # @param versions [Range, Array, Integer] The version range to format
    # @return [String] A human-readable version range
    def format_version_range(versions)
      if versions.is_a?(Range)
        if versions.end.nil?
          "#{versions.begin} and above"
        else
          "#{versions.begin} to #{versions.end}#{versions.exclude_end? ? ' (exclusive)' : ''}"
        end
      elsif versions.is_a?(Array)
        versions.join(", ")
      else
        versions.to_s
      end
    end
  end
end