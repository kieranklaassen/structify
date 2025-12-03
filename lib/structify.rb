# frozen_string_literal: true

require "ruby_llm/schema"
require_relative "structify/version"
require_relative "structify/field_validation"
require_relative "structify/model"

module Structify
  class << self
    attr_accessor :default_container_attribute
  end
  self.default_container_attribute = :json_attributes

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
