# frozen_string_literal: true

require_relative "structify/version"
require_relative "structify/schema_serializer"
require_relative "structify/field_validation"
require_relative "structify/model"

# Structify is a DSL for defining extraction schemas for LLM-powered models.
# It provides a simple way to integrate with Rails models for LLM extraction,
# allowing for schema versioning and evolution.
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
module Structify
  # Configuration class for Structify
  class Configuration
    # @return [Symbol] The default container attribute for JSON fields
    attr_accessor :default_container_attribute
    
    # @return [Boolean] Whether to validate data against schema on save
    attr_accessor :validate_on_save
    
    # @return [Boolean] Whether to raise exceptions on validation failure instead of adding errors
    attr_accessor :strict_validation
    
    def initialize
      @default_container_attribute = :json_attributes
      @validate_on_save = true  # Enable validation by default
      @strict_validation = false  # Add errors instead of raising by default
    end
  end
  
  # @return [Structify::Configuration] The current configuration
  def self.configuration
    @configuration ||= Configuration.new
  end
  
  # Configure Structify
  # @yield [config] The configuration block
  # @yieldparam config [Structify::Configuration] The configuration object
  # @return [Structify::Configuration] The updated configuration
  def self.configure
    yield(configuration) if block_given?
    configuration
  end
  # Base error class for Structify
  class Error < StandardError; end
  
  # Error raised when trying to access a field that doesn't exist in the record's version
  class MissingFieldError < Error
    attr_reader :field_name, :record_version, :schema_version
    
    def initialize(field_name, record_version, schema_version)
      @field_name = field_name
      @record_version = record_version
      @schema_version = schema_version
      
      message = "Field '#{field_name}' does not exist in version #{record_version}. " \
                "It was introduced in version #{schema_version}. " \
                "To access this field, upgrade the record by setting new field values and saving."
      
      super(message)
    end
  end
  
  # Error raised when trying to access a field that has been removed in the current schema version
  class RemovedFieldError < Error
    attr_reader :field_name, :removed_in_version
    
    def initialize(field_name, removed_in_version)
      @field_name = field_name
      @removed_in_version = removed_in_version
      
      message = "Field '#{field_name}' has been removed in version #{removed_in_version}. " \
                "This field is no longer available in the current schema."
      
      super(message)
    end
  end
  
  # Error raised when trying to access a field outside its specified version range
  class VersionRangeError < Error
    attr_reader :field_name, :record_version, :valid_versions
    
    def initialize(field_name, record_version, valid_versions)
      @field_name = field_name
      @record_version = record_version
      @valid_versions = valid_versions
      
      message = "Field '#{field_name}' is not available in version #{record_version}. " \
                "This field is only available in versions: #{format_versions(valid_versions)}."
      
      super(message)
    end
    
    private
    
    def format_versions(versions)
      if versions.is_a?(Range)
        if versions.end.nil?
          "#{versions.begin} and above"
        else
          "#{versions.begin} to #{versions.end}#{versions.exclude_end? ? ' (exclusive)' : ''}"
        end
      elsif versions.is_a?(Array)
        versions.join(", ")
      else
        "#{versions} and above"  # Single integer means this version and onwards
      end
    end
  end

  # Base exception for all validation errors from LLM responses
  class LLMValidationError < Error
    attr_reader :field_name, :value, :record
    
    def initialize(field_name, value, message, record: nil)
      @field_name = field_name
      @value = value
      @record = record
      super(message)
    end
  end
  
  # Error raised when LLM returns wrong data type
  class TypeMismatchError < LLMValidationError
    attr_reader :expected_type, :actual_type
    
    def initialize(field_name, value, expected_type, actual_type, record: nil)
      @expected_type = expected_type
      @actual_type = actual_type
      
      message = "Field '#{field_name}' expected #{expected_type}, got #{actual_type}: #{value.inspect}"
      super(field_name, value, message, record: record)
    end
  end
  
  # Error raised when required field is missing
  class RequiredFieldError < LLMValidationError
    def initialize(field_name, record: nil)
      message = "Required field '#{field_name}' is missing or nil"
      super(field_name, nil, message, record: record)
    end
  end
  
  # Error raised when enum value is invalid
  class EnumValidationError < LLMValidationError
    attr_reader :allowed_values
    
    def initialize(field_name, value, allowed_values, record: nil)
      @allowed_values = allowed_values
      message = "Field '#{field_name}' value #{value.inspect} is not in allowed values: #{allowed_values.inspect}"
      super(field_name, value, message, record: record)
    end
  end
  
  # Error raised when array constraints are violated
  class ArrayConstraintError < LLMValidationError
    def initialize(field_name, value, constraint_message, record: nil)
      message = "Field '#{field_name}' array constraint violation: #{constraint_message}"
      super(field_name, value, message, record: record)
    end
  end
  
  # Error raised when object property validation fails
  class ObjectValidationError < LLMValidationError
    attr_reader :property_name
    
    def initialize(field_name, value, property_name, property_message, record: nil)
      @property_name = property_name
      message = "Field '#{field_name}' object validation failed for property '#{property_name}': #{property_message}"
      super(field_name, value, message, record: record)
    end
  end
end
