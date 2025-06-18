# frozen_string_literal: true

require "active_support/concern"

module Structify
  # Module that provides always-on validation for Structify fields against the defined schema.
  # 
  # This module is automatically included in models that use Structify::Model and validates
  # all LLM responses to ensure they conform to the schema definition. It raises specific
  # exceptions for different validation failures to enable retry logic.
  #
  # @example Basic usage with validation errors
  #   class Article < ApplicationRecord
  #     include Structify::Model
  #
  #     schema_definition do
  #       field :title, :string, required: true
  #       field :category, :string, enum: ["tech", "business", "science"]
  #       field :tags, :array, items: { type: "string" }, min_items: 1
  #     end
  #   end
  #
  #   # These will raise validation errors:
  #   article = Article.new
  #   article.title = 123  # TypeMismatchError: expected string, got integer
  #   article.category = "invalid"  # EnumValidationError: not in allowed values
  #   article.tags = []  # ArrayConstraintError: must have at least 1 items
  #
  # @example Handling validation errors for LLM retries
  #   begin
  #     article.update!(llm_response)
  #   rescue Structify::TypeMismatchError => e
  #     Rails.logger.warn "Type mismatch for #{e.field_name}: #{e.message}"
  #     retry_with_better_prompt(e.field_name, e.expected_type)
  #   rescue Structify::RequiredFieldError => e
  #     Rails.logger.warn "Missing required field: #{e.message}"
  #     retry_with_explicit_requirement(e.field_name)
  #   end
  #
  # @example Complex object validation
  #   schema_definition do
  #     field :author, :object, required: true, properties: {
  #       "name" => { type: "string", required: true },
  #       "email" => { type: "string" }
  #     }
  #     field :activities, :array, items: {
  #       type: "object",
  #       properties: {
  #         "title" => { type: "string", required: true },
  #         "impact" => { type: "integer", required: true }
  #       }
  #     }
  #   end
  #
  #   # Invalid: missing required object property
  #   article.author = { email: "test@example.com" }  # ObjectValidationError: missing required property 'name'
  #   
  #   # Invalid: array item missing required property
  #   article.activities = [{ title: "Test" }]  # ArrayConstraintError: missing required property 'impact'
  #
  # @see Structify::LLMValidationError Base class for all validation errors
  # @see Structify::TypeMismatchError For type validation failures
  # @see Structify::RequiredFieldError For missing required fields
  # @see Structify::EnumValidationError For invalid enum values
  # @see Structify::ArrayConstraintError For array validation failures
  # @see Structify::ObjectValidationError For object property validation failures
  module FieldValidation
    extend ActiveSupport::Concern
    
    included do
      validate :validate_structify_fields
    end
    
    private
    
    # Main validation method that validates all fields defined in the schema.
    # Called automatically by ActiveRecord during validation lifecycle.
    #
    # @return [void]
    # @raise [Structify::LLMValidationError] When any field validation fails
    def validate_structify_fields
      return unless self.class.schema_builder
      
      self.class.schema_builder.fields.each do |field_def|
        validate_field(field_def)
      end
    end
    
    # Validate a single field against its definition.
    #
    # @param field_def [Hash] The field definition from schema_builder
    # @option field_def [Symbol] :name The field name
    # @option field_def [Symbol] :type The expected type (:string, :integer, :array, etc.)
    # @option field_def [Boolean] :required Whether the field is required
    # @option field_def [Array] :enum Allowed enum values
    # @option field_def [Hash] :items Schema for array items
    # @option field_def [Hash] :properties Schema for object properties
    # @return [void]
    # @raise [Structify::LLMValidationError] When validation fails
    def validate_field(field_def)
      field_name = field_def[:name]
      
      # Skip if field not accessible in current version
      return unless version_field_accessible?(field_def)
      
      begin
        value = read_field_value(field_name)
      rescue VersionRangeError, RemovedFieldError
        # Field is not accessible in this version, skip validation
        return
      end
      
      # Required field validation
      validate_required_field(field_name, value, field_def[:required])
      
      return if value.nil?
      
      # Type validation
      validate_field_type(field_name, value, field_def[:type])
      
      # Enum validation
      validate_enum_field(field_name, value, field_def[:enum]) if field_def[:enum]
      
      # Array constraints
      validate_array_constraints(field_name, value, field_def) if field_def[:type] == :array
      
      # Object validation
      validate_object_properties(field_name, value, field_def) if field_def[:type] == :object
    end
    
    # Check if a field is accessible in the current record's version
    def version_field_accessible?(field_def)
      return true unless field_def[:version_range]
      
      record_version = stored_version
      version_in_range?(record_version, field_def[:version_range])
    end
    
    # Safely read a field value, handling version errors
    def read_field_value(field_name)
      send(field_name)
    rescue NoMethodError
      # Field accessor doesn't exist, return nil
      nil
    end
    
    # Validate that required fields are present.
    #
    # @param field_name [Symbol] The name of the field being validated
    # @param value [Object] The field value
    # @param required [Boolean] Whether the field is required
    # @return [void]
    # @raise [Structify::RequiredFieldError] When required field is missing
    def validate_required_field(field_name, value, required)
      if required && (value.nil? || (value.respond_to?(:empty?) && value.empty?))
        raise RequiredFieldError.new(field_name, record: self)
      end
    end
    
    # Validate field type matches expected type.
    #
    # @param field_name [Symbol] The name of the field being validated
    # @param value [Object] The field value
    # @param expected_type [Symbol] Expected type (:string, :integer, :array, etc.)
    # @return [void]
    # @raise [Structify::TypeMismatchError] When value type doesn't match expected type
    def validate_field_type(field_name, value, expected_type)
      valid = case expected_type
              when :string, :text
                value.is_a?(String)
              when :integer
                value.is_a?(Integer)
              when :number
                value.is_a?(Numeric)
              when :boolean
                value.is_a?(TrueClass) || value.is_a?(FalseClass)
              when :array
                value.is_a?(Array)
              when :object
                value.is_a?(Hash)
              else
                true
              end
      
      unless valid
        actual_type = value.class.name.downcase
        actual_type = "boolean" if [TrueClass, FalseClass].include?(value.class)
        
        raise TypeMismatchError.new(
          field_name,
          value,
          expected_type,
          actual_type,
          record: self
        )
      end
    end
    
    # Validate enum field values
    def validate_enum_field(field_name, value, allowed_values)
      # Allow nil for optional enum fields
      return if value.nil?
      
      unless allowed_values.include?(value)
        raise EnumValidationError.new(
          field_name,
          value,
          allowed_values,
          record: self
        )
      end
    end
    
    # Validate array constraints (min_items, max_items, unique_items)
    def validate_array_constraints(field_name, array, field_def)
      return unless array.is_a?(Array)
      
      min_items = field_def[:min_items]
      max_items = field_def[:max_items]
      unique_items = field_def[:unique_items]
      items_schema = field_def[:items]
      
      # Validate min_items
      if min_items && array.length < min_items
        raise ArrayConstraintError.new(
          field_name,
          array,
          "must have at least #{min_items} items, got #{array.length}",
          record: self
        )
      end
      
      # Validate max_items
      if max_items && array.length > max_items
        raise ArrayConstraintError.new(
          field_name,
          array,
          "must have at most #{max_items} items, got #{array.length}",
          record: self
        )
      end
      
      # Validate unique_items
      if unique_items && array.uniq.length != array.length
        raise ArrayConstraintError.new(
          field_name,
          array,
          "items must be unique",
          record: self
        )
      end
      
      # Validate items schema
      if items_schema
        validate_array_items(field_name, array, items_schema)
      end
    end
    
    # Validate individual array items against schema
    def validate_array_items(field_name, array, items_schema)
      array.each_with_index do |item, index|
        # Type validation for array items
        if items_schema[:type] || items_schema["type"]
          item_type = items_schema[:type] || items_schema["type"]
          validate_array_item_type(field_name, item, item_type, index)
        end
        
        # Enum validation for array items
        if items_schema[:enum] || items_schema["enum"]
          item_enum = items_schema[:enum] || items_schema["enum"]
          validate_array_item_enum(field_name, item, item_enum, index)
        end
        
        # Object validation for array items
        if item_type == "object" && (items_schema[:properties] || items_schema["properties"])
          item_properties = items_schema[:properties] || items_schema["properties"]
          validate_array_item_object(field_name, item, item_properties, index)
        end
      end
    end
    
    # Validate array item type
    def validate_array_item_type(field_name, item, expected_type, index)
      expected_type = expected_type.to_s if expected_type.is_a?(Symbol)
      
      valid = case expected_type
              when "string"
                item.is_a?(String)
              when "integer"
                item.is_a?(Integer)
              when "number"
                item.is_a?(Numeric)
              when "boolean"
                item.is_a?(TrueClass) || item.is_a?(FalseClass)
              when "object"
                item.is_a?(Hash)
              when "array"
                item.is_a?(Array)
              else
                true
              end
      
      unless valid
        actual_type = item.class.name.downcase
        actual_type = "boolean" if [TrueClass, FalseClass].include?(item.class)
        
        raise ArrayConstraintError.new(
          field_name,
          item,
          "item at index #{index} expected #{expected_type}, got #{actual_type}: #{item.inspect}",
          record: self
        )
      end
    end
    
    # Validate array item enum values
    def validate_array_item_enum(field_name, item, allowed_values, index)
      unless allowed_values.include?(item)
        raise ArrayConstraintError.new(
          field_name,
          item,
          "item at index #{index} value #{item.inspect} is not in allowed values: #{allowed_values.inspect}",
          record: self
        )
      end
    end
    
    # Validate array item object properties
    def validate_array_item_object(field_name, item, properties_schema, index)
      return unless item.is_a?(Hash)
      
      properties_schema.each do |prop_name, prop_schema|
        prop_value = item[prop_name.to_s] || item[prop_name.to_sym]
        
        # Check required properties
        if (prop_schema[:required] || prop_schema["required"]) && prop_value.nil?
          raise ArrayConstraintError.new(
            field_name,
            item,
            "item at index #{index} is missing required property '#{prop_name}'",
            record: self
          )
        end
        
        # Validate property type if present
        if prop_value && (prop_schema[:type] || prop_schema["type"])
          prop_type = prop_schema[:type] || prop_schema["type"]
          validate_object_property_type(field_name, prop_name, prop_value, prop_type, "item at index #{index}")
        end
      end
    end
    
    # Validate object properties against schema
    def validate_object_properties(field_name, object, field_def)
      properties_schema = field_def[:properties]
      return unless object.is_a?(Hash) && properties_schema
      
      properties_schema.each do |prop_name, prop_schema|
        prop_value = object[prop_name.to_s] || object[prop_name.to_sym]
        
        # Check required properties
        if (prop_schema[:required] || prop_schema["required"]) && prop_value.nil?
          raise ObjectValidationError.new(
            field_name,
            object,
            prop_name,
            "required property is missing",
            record: self
          )
        end
        
        # Validate property type if present
        if prop_value && (prop_schema[:type] || prop_schema["type"])
          prop_type = prop_schema[:type] || prop_schema["type"]
          validate_object_property_type(field_name, prop_name, prop_value, prop_type)
        end
        
        # Validate property enum if present
        if prop_value && (prop_schema[:enum] || prop_schema["enum"])
          prop_enum = prop_schema[:enum] || prop_schema["enum"]
          validate_object_property_enum(field_name, prop_name, prop_value, prop_enum)
        end
      end
    end
    
    # Validate object property type
    def validate_object_property_type(field_name, prop_name, prop_value, expected_type, context = nil)
      expected_type = expected_type.to_s if expected_type.is_a?(Symbol)
      
      valid = case expected_type
              when "string"
                prop_value.is_a?(String)
              when "integer"
                prop_value.is_a?(Integer)
              when "number"
                prop_value.is_a?(Numeric)
              when "boolean"
                prop_value.is_a?(TrueClass) || prop_value.is_a?(FalseClass)
              when "object"
                prop_value.is_a?(Hash)
              when "array"
                prop_value.is_a?(Array)
              else
                true
              end
      
      unless valid
        actual_type = prop_value.class.name.downcase
        actual_type = "boolean" if [TrueClass, FalseClass].include?(prop_value.class)
        
        property_message = "property '#{prop_name}' expected #{expected_type}, got #{actual_type}: #{prop_value.inspect}"
        property_message = "#{context} #{property_message}" if context
        
        if context
          # This is from an array item validation
          raise ArrayConstraintError.new(
            field_name,
            prop_value,
            property_message,
            record: self
          )
        else
          raise ObjectValidationError.new(
            field_name,
            prop_value,
            prop_name,
            "expected #{expected_type}, got #{actual_type}: #{prop_value.inspect}",
            record: self
          )
        end
      end
    end
    
    # Validate object property enum values
    def validate_object_property_enum(field_name, prop_name, prop_value, allowed_values)
      unless allowed_values.include?(prop_value)
        raise ObjectValidationError.new(
          field_name,
          prop_value,
          prop_name,
          "value #{prop_value.inspect} is not in allowed values: #{allowed_values.inspect}",
          record: self
        )
      end
    end
  end
end