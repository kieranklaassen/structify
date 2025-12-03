# frozen_string_literal: true

require "ruby_llm/schema"
require_relative "structify/version"
require_relative "structify/field_validation"
require_relative "structify/model"

# Structify is a DSL for defining extraction schemas for LLM-powered models.
# It wraps RubyLLM::Schema to provide ActiveRecord integration and validation.
#
# @example
#   class Article < ApplicationRecord
#     include Structify::Model
#
#     schema_definition do
#       name "ArticleExtraction"
#       description "Extract article metadata"
#
#       string :title, description: "The article title"
#       string :summary, required: false
#       array :tags, of: :string, min_items: 1
#     end
#   end
module Structify
  # Configuration class for Structify
  class Configuration
    # @return [Symbol] The default container attribute for JSON fields
    attr_accessor :default_container_attribute

    def initialize
      @default_container_attribute = :json_attributes
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
