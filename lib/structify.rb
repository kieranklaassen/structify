# frozen_string_literal: true

require_relative "structify/version"
require_relative "structify/schema_serializer"
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
end
