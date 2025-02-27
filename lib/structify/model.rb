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

      # Store all extracted data in the extracted_data JSON column
      attr_json_config(default_container_attribute: :extracted_data)
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
    attr_reader :model, :fields, :title_str, :description_str, :version_number

    # Initialize a new SchemaBuilder
    #
    # @param model [Class] The model class
    def initialize(model)
      @model = model
      @fields = []
      @version_number = 1
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
      model.attribute :version, :integer, default: num
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
    # @return [void]
    def field(name, type, required: false, description: nil, enum: nil, 
              items: nil, properties: nil, min_items: nil, max_items: nil, 
              unique_items: nil)
      field_definition = {
        name: name,
        type: type,
        required: required,
        description: description
      }
      
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

      model.attr_json name, attr_type
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