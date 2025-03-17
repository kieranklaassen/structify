# frozen_string_literal: true

require "active_support/concern"
require "active_support/core_ext/class/attribute"
require "attr_json"
require_relative "schema_serializer"

module Structify
  # The Model module provides a DSL for defining LLM extraction schemas in your Rails models.
  # It allows you to define fields, versioning, and validation for LLM-based data extraction.
  #
  # @example
  #   class Article < ApplicationRecord
  #     include Structify::Model
  #
  #     schema_definition do
  #       title "Article Extraction"
  #       description "Extract article metadata"
  #       version 1
  #
  #       field :title, :string, required: true
  #       field :summary, :text, description: "A brief summary of the article"
  #       field :category, :string, enum: ["tech", "business", "science"]
  #     end
  #   end
  module Model
    extend ActiveSupport::Concern

    included do
      include AttrJson::Record
      class_attribute :schema_builder, instance_writer: false, default: nil

      # Use the configured default container attribute
      attr_json_config(default_container_attribute: Structify.configuration.default_container_attribute)
    end
    
    # Instance methods
    def version_compatible_with?(required_version)
      container_attribute = self.class.attr_json_config.default_container_attribute
      record_data = self.send(container_attribute) || {}
      record_version = record_data["version"] || 1
      record_version >= required_version
    end
    
    # Get the stored version of this record
    def stored_version
      container_attribute = self.class.attr_json_config.default_container_attribute
      record_data = self.send(container_attribute) || {}
      record_data["version"] || 1
    end
    
    # Check if a version is within a given range/array of versions
    # This is used in field accessors to check version compatibility
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

    # Class methods added to the including class
    module ClassMethods
      # Define the schema for LLM extraction
      #
      # @yield [void] The schema definition block
      # @return [void]
      def schema_definition(&block)
        self.schema_builder ||= SchemaBuilder.new(self)
        schema_builder.instance_eval(&block) if block_given?
      end

      # Get the JSON schema representation
      #
      # @return [Hash] The JSON schema
      def json_schema
        schema_builder&.to_json_schema
      end

      # Get the current extraction version
      #
      # @return [Integer] The version number
      def extraction_version
        schema_builder&.version_number
      end

    end
  end

  # Builder class for constructing the schema
  class SchemaBuilder
    # @return [Class] The model class
    # @return [Array<Hash>] The field definitions
    # @return [String] The schema title
    # @return [String] The schema description
    # @return [Integer] The schema version
    # @return [Boolean] Whether thinking mode is enabled
    attr_reader :model, :fields, :title_str, :description_str, :version_number, :thinking_enabled

    # Initialize a new SchemaBuilder
    #
    # @param model [Class] The model class
    def initialize(model)
      @model = model
      @fields = []
      @version_number = 1
      @thinking_enabled = false
    end
    
    # Enable or disable thinking mode
    # When enabled, the LLM will be asked to provide chain of thought reasoning
    #
    # @param enabled [Boolean] Whether to enable thinking mode
    # @return [void]
    def thinking(enabled)
      @thinking_enabled = enabled
    end

    # Set the schema title
    #
    # @param name [String] The title
    # @return [void]
    def title(name)
      @title_str = name
    end

    # Set the schema description
    #
    # @param desc [String] The description
    # @return [void]
    def description(desc)
      @description_str = desc
    end

    # Set the schema version
    #
    # @param num [Integer] The version number
    # @return [void]
    def version(num)
      @version_number = num
      
      # Define version as an attr_json field so it's stored in extracted_data
      model.attr_json :version, :integer, default: num
      
      # Store mapping of fields to their introduction version
      @fields_by_version ||= {}
      @fields_by_version[num] ||= []
    end


    # Define a field in the schema
    #
    # @param name [Symbol] The field name
    # @param type [Symbol] The field type
    # @param required [Boolean] Whether the field is required
    # @param description [String] The field description
    # @param enum [Array] Possible values for the field
    # @param items [Hash] For array type, defines the schema for array items
    # @param properties [Hash] For object type, defines the properties of the object
    # @param min_items [Integer] For array type, minimum number of items
    # @param max_items [Integer] For array type, maximum number of items
    # @param unique_items [Boolean] For array type, whether items must be unique
    # @param versions [Range, Array, Integer] The versions this field is available in (default: current version onwards)
    # @return [void]
    def field(name, type, required: false, description: nil, enum: nil, 
              items: nil, properties: nil, min_items: nil, max_items: nil, 
              unique_items: nil, versions: nil)
      
      # Handle version information
      version_range = if versions
                        # Use the versions parameter if provided
                        versions
                      else
                        # Default: field is available in all versions
                        1..999
                      end
      
      # Check if the field is applicable for the current schema version
      field_available = version_in_range?(@version_number, version_range)
      
      # Skip defining the field in the schema if it's not applicable to the current version
      unless field_available
        # Still define an accessor that raises an appropriate error
        define_version_range_accessor(name, version_range)
        return
      end
      
      # Calculate a simple introduced_in for backward compatibility
      effective_introduced_in = case version_range
                               when Range
                                 version_range.begin
                               when Array
                                 version_range.min
                               else
                                 version_range
                               end
      
      field_definition = {
        name: name,
        type: type,
        required: required,
        description: description,
        version_range: version_range,
        introduced_in: effective_introduced_in
      }
      
      # Add enum if provided
      field_definition[:enum] = enum if enum
      
      # Array specific properties
      if type == :array
        field_definition[:items] = items if items
        field_definition[:min_items] = min_items if min_items
        field_definition[:max_items] = max_items if max_items
        field_definition[:unique_items] = unique_items if unique_items
      end
      
      # Object specific properties
      if type == :object
        field_definition[:properties] = properties if properties
      end
      
      fields << field_definition
      
      # Track field by its version range
      @fields_by_version ||= {}
      @fields_by_version[effective_introduced_in] ||= []
      @fields_by_version[effective_introduced_in] << name

      # Map JSON Schema types to Ruby/AttrJson types
      attr_type = case type
                  when :integer, :number
                    :integer
                  when :array
                    :json
                  when :object
                    :json
                  when :boolean
                    :boolean
                  else
                    type # string, text stay the same
                  end

      # Define custom accessor that checks version compatibility
      define_version_range_accessors(name, attr_type, version_range)
    end
    
    # Check if a version is within a given range/array of versions
    #
    # @param version [Integer] The version to check
    # @param range [Range, Array, Integer] The range, array, or single version to check against
    # @return [Boolean] Whether the version is within the range
    def version_in_range?(version, range)
      case range
      when Range
        # Handle endless ranges (Ruby 2.6+): 2.. means 2 and above
        if range.end.nil?
          version >= range.begin
        else
          range.cover?(version)
        end
      when Array
        range.include?(version)
      else
        # A single integer means "this version and onwards"
        version >= range
      end
    end
    
    # Define accessor methods that check version compatibility using the new version ranges
    #
    # @param name [Symbol] The field name
    # @param type [Symbol] The field type for attr_json
    # @param version_range [Range, Array, Integer] The versions this field is available in
    # @return [void]
    def define_version_range_accessors(name, type, version_range)
      # Define the attr_json normally first
      model.attr_json name, type
      
      # Extract current version for error messages
      schema_version = @version_number
      
      # Then override the reader method to check versions
      model.class_eval <<-RUBY, __FILE__, __LINE__ + 1
        # Store original method
        alias_method :_original_#{name}, :#{name}
        
        # Override reader to check version compatibility
        def #{name}
          # Get the container attribute and data
          container_attribute = self.class.attr_json_config.default_container_attribute
          record_data = self.send(container_attribute)
          
          # Get the version from the record data
          record_version = record_data && record_data["version"] ? 
                           record_data["version"] : 1
          
          # Check if record version is compatible with field's version range
          field_version_range = #{version_range.inspect}
          
          # Handle field lifecycle based on version
          unless version_in_range?(record_version, field_version_range)
            # Check if this is a removed field (was valid in earlier versions but not current version)
            if field_version_range.is_a?(Range) && field_version_range.begin <= record_version && field_version_range.end < #{schema_version}
              raise Structify::RemovedFieldError.new(
                "#{name}", 
                field_version_range.end
              )
            # Check if this is a new field (only valid in later versions)
            elsif (field_version_range.is_a?(Range) && field_version_range.begin > record_version) ||
                  (field_version_range.is_a?(Integer) && field_version_range > record_version)
              raise Structify::VersionRangeError.new(
                "#{name}", 
                record_version,
                field_version_range
              )
            # Otherwise it's just not in the valid range
            else
              raise Structify::VersionRangeError.new(
                "#{name}", 
                record_version, 
                field_version_range
              )
            end
          end
          
          # Check for deprecated fields and show warning
          if field_version_range.is_a?(Range) && 
             field_version_range.begin < #{schema_version} && 
             field_version_range.end < 999 && 
             field_version_range.cover?(record_version)
            ActiveSupport::Deprecation.warn(
              "Field '#{name}' is deprecated as of version #{schema_version} and will be removed in version \#{field_version_range.end}."
            )
          end
          
          # Call original method
          _original_#{name}
        end
      RUBY
    end
    
    # Define accessor for fields that are not in the current schema version
    # These will raise an appropriate error when accessed
    #
    # @param name [Symbol] The field name
    # @param version_range [Range, Array, Integer] The versions this field is available in
    # @return [void]
    def define_version_range_accessor(name, version_range)
      # Capture schema version to use in the eval block
      schema_version = @version_number
      
      # Handle different version range types
      version_range_type = case version_range
                          when Range
                            "range"
                          when Array
                            "array"
                          else
                            "integer"
                          end
                          
      # Extract begin/end values for ranges
      range_begin = case version_range
                    when Range
                      version_range.begin
                    when Array
                      version_range.min
                    else
                      version_range
                    end
                    
      range_end = case version_range
                  when Range
                    version_range.end
                  when Array
                    version_range.max
                  else
                    version_range
                  end
      
      model.class_eval <<-RUBY, __FILE__, __LINE__ + 1
        # Define an accessor that raises an error when accessed
        def #{name}
          # Based on the version_range type, create appropriate errors
          case "#{version_range_type}"
          when "range"
            if #{range_begin} <= #{schema_version} && #{range_end} < #{schema_version}
              # Removed field
              raise Structify::RemovedFieldError.new("#{name}", #{range_end})
            elsif #{range_begin} > #{schema_version}
              # Field from future version
              raise Structify::VersionRangeError.new("#{name}", #{schema_version}, #{version_range.inspect})
            else
              # Not in range for other reasons
              raise Structify::VersionRangeError.new("#{name}", #{schema_version}, #{version_range.inspect})
            end
          when "array"
            # For arrays, we can only check if the current version is in the array
            raise Structify::VersionRangeError.new("#{name}", #{schema_version}, #{version_range.inspect})
          else
            # For integers, just report version mismatch
            raise Structify::VersionRangeError.new("#{name}", #{schema_version}, #{version_range.inspect})
          end
        end
        
        # Define a writer that raises an error too
        def #{name}=(value)
          # Use the same error logic as the reader
          self.#{name}
        end
      RUBY
    end

    # Generate the JSON schema representation
    #
    # @return [Hash] The JSON schema
    def to_json_schema
      serializer = SchemaSerializer.new(self)
      serializer.to_json_schema
    end
  end
end