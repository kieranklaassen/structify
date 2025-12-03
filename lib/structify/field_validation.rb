# frozen_string_literal: true

require "active_support/concern"

module Structify
  # Module that provides always-on validation for Structify fields against the defined schema.
  #
  # This module is automatically included in models that use Structify::Model and validates
  # all LLM responses to ensure they conform to the schema definition.
  #
  # @example Basic usage with validation errors
  #   class Article < ApplicationRecord
  #     include Structify::Model
  #
  #     schema_definition do
  #       string :title
  #       string :category, enum: ["tech", "business", "science"]
  #       array :tags, of: :string, min_items: 1
  #     end
  #   end
  #
  #   # These will raise validation errors:
  #   article = Article.new
  #   article.title = 123  # TypeMismatchError: expected string, got integer
  #   article.category = "invalid"  # EnumValidationError: not in allowed values
  #   article.tags = []  # ArrayConstraintError: must have at least 1 items
  module FieldValidation
    extend ActiveSupport::Concern

    included do
      validate :validate_structify_fields
    end

    private

    # Main validation method that validates all fields defined in the schema.
    def validate_structify_fields
      return unless self.class.structify_schema

      schema_hash = self.class.structify_schema.new.to_json_schema
      # ruby_llm-schema nests properties under :schema
      schema_object = schema_hash[:schema] || schema_hash["schema"] || schema_hash
      properties = schema_object[:properties] || schema_object["properties"] || {}
      required_fields = schema_object[:required] || schema_object["required"] || []
      # Convert required fields to strings for comparison
      required_strings = required_fields.map(&:to_s)

      properties.each do |field_name, field_def|
        validate_field(field_name.to_sym, field_def, required_strings.include?(field_name.to_s))
      end
    end

    # Validate a single field against its definition.
    def validate_field(field_name, field_def, is_required)
      value = send(field_name) rescue nil

      # Required field validation
      validate_required_field(field_name, value, is_required)

      return if value.nil?

      field_type = field_def[:type] || field_def["type"]

      # Type validation
      validate_field_type(field_name, value, field_type)

      # Enum validation
      enum_values = field_def[:enum] || field_def["enum"]
      validate_enum_field(field_name, value, enum_values) if enum_values

      # Array constraints
      if field_type == "array"
        validate_array_constraints(field_name, value, field_def)
      end

      # Object validation
      if field_type == "object"
        validate_object_properties(field_name, value, field_def)
      end
    end

    # Validate that required fields are present.
    def validate_required_field(field_name, value, required)
      if required && (value.nil? || (value.respond_to?(:empty?) && value.empty?))
        raise RequiredFieldError.new(field_name, record: self)
      end
    end

    # Validate field type matches expected type.
    def validate_field_type(field_name, value, expected_type)
      valid = case expected_type.to_s
              when "string"
                value.is_a?(String)
              when "integer"
                value.is_a?(Integer)
              when "number"
                value.is_a?(Numeric)
              when "boolean"
                value.is_a?(TrueClass) || value.is_a?(FalseClass)
              when "array"
                value.is_a?(Array)
              when "object"
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

    # Validate array constraints (minItems, maxItems, uniqueItems)
    def validate_array_constraints(field_name, array, field_def)
      return unless array.is_a?(Array)

      min_items = field_def[:minItems] || field_def["minItems"]
      max_items = field_def[:maxItems] || field_def["maxItems"]
      unique_items = field_def[:uniqueItems] || field_def["uniqueItems"]
      items_schema = field_def[:items] || field_def["items"]

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
      item_type = items_schema[:type] || items_schema["type"]

      array.each_with_index do |item, index|
        # Type validation for array items
        if item_type
          validate_array_item_type(field_name, item, item_type, index)
        end

        # Enum validation for array items
        item_enum = items_schema[:enum] || items_schema["enum"]
        if item_enum
          validate_array_item_enum(field_name, item, item_enum, index)
        end

        # Object validation for array items
        if item_type == "object"
          item_properties = items_schema[:properties] || items_schema["properties"]
          if item_properties
            validate_array_item_object(field_name, item, items_schema, index)
          end
        end
      end
    end

    # Validate array item type
    def validate_array_item_type(field_name, item, expected_type, index)
      valid = case expected_type.to_s
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
    def validate_array_item_object(field_name, item, items_schema, index)
      return unless item.is_a?(Hash)

      properties_schema = items_schema[:properties] || items_schema["properties"]
      return unless properties_schema

      # Get required properties from the items schema (convert to strings for comparison)
      required_props = (items_schema[:required] || items_schema["required"] || []).map(&:to_s)

      properties_schema.each do |prop_name, prop_schema|
        prop_value = item[prop_name.to_s] || item[prop_name.to_sym]

        # Check required properties
        if required_props.include?(prop_name.to_s) && prop_value.nil?
          raise ArrayConstraintError.new(
            field_name,
            item,
            "item at index #{index} is missing required property '#{prop_name}'",
            record: self
          )
        end

        # Validate property type if present
        prop_type = prop_schema[:type] || prop_schema["type"]
        if prop_value && prop_type
          validate_object_property_type(field_name, prop_name, prop_value, prop_type, "item at index #{index}")
        end
      end
    end

    # Validate object properties against schema
    def validate_object_properties(field_name, object, field_def)
      properties_schema = field_def[:properties] || field_def["properties"]
      return unless object.is_a?(Hash) && properties_schema

      # Get required properties (convert to strings for comparison)
      required_props = (field_def[:required] || field_def["required"] || []).map(&:to_s)

      properties_schema.each do |prop_name, prop_schema|
        prop_value = object[prop_name.to_s] || object[prop_name.to_sym]

        # Check required properties
        if required_props.include?(prop_name.to_s) && prop_value.nil?
          raise ObjectValidationError.new(
            field_name,
            object,
            prop_name.to_s,
            "required property is missing",
            record: self
          )
        end

        # Validate property type if present
        prop_type = prop_schema[:type] || prop_schema["type"]
        if prop_value && prop_type
          validate_object_property_type(field_name, prop_name, prop_value, prop_type)
        end

        # Validate property enum if present
        prop_enum = prop_schema[:enum] || prop_schema["enum"]
        if prop_value && prop_enum
          validate_object_property_enum(field_name, prop_name, prop_value, prop_enum)
        end
      end
    end

    # Validate object property type
    def validate_object_property_type(field_name, prop_name, prop_value, expected_type, context = nil)
      valid = case expected_type.to_s
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
            prop_name.to_s,
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
          prop_name.to_s,
          "value #{prop_value.inspect} is not in allowed values: #{allowed_values.inspect}",
          record: self
        )
      end
    end
  end
end
