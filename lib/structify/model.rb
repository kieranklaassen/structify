# frozen_string_literal: true

require "active_support/concern"
require "active_support/core_ext/class/attribute"
require "attr_json"
require "ruby_llm/schema"

module Structify
  # The Model module provides a DSL for defining LLM extraction schemas in your Rails models.
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
  #
  #       object :author do
  #         string :name
  #         string :email, required: false
  #       end
  #     end
  #   end
  module Model
    extend ActiveSupport::Concern

    included do
      include AttrJson::Record
      include Structify::FieldValidation

      class_attribute :structify_schema, instance_writer: false, default: nil

      # Use the configured default container attribute
      attr_json_config(default_container_attribute: Structify.configuration.default_container_attribute)
    end

    # Check if the extracted data has been changed since the record was last saved
    #
    # @return [Boolean] Whether the extracted data has changed
    def saved_change_to_extracted_data?
      container_attribute = self.class.attr_json_config.default_container_attribute
      respond_to?("saved_change_to_#{container_attribute}?") &&
        send("saved_change_to_#{container_attribute}?")
    end

    # Class methods added to the including class
    module ClassMethods
      # Define the schema for LLM extraction using RubyLLM::Schema DSL
      #
      # @yield The schema definition block using RubyLLM::Schema DSL
      # @return [void]
      def schema_definition(&block)
        # Create a RubyLLM::Schema subclass dynamically
        schema_class = Class.new(RubyLLM::Schema)
        schema_class.class_eval(&block) if block_given?

        self.structify_schema = schema_class

        # Create attr_json fields from schema properties
        create_attr_json_fields_from_schema
      end

      # Get the JSON schema representation
      # Returns a flattened format compatible with LLM APIs
      #
      # @return [Hash] The JSON schema
      def json_schema
        return nil unless structify_schema

        raw_schema = structify_schema.new.to_json_schema
        schema_object = raw_schema[:schema] || raw_schema["schema"] || {}

        required_fields = schema_object[:required] || schema_object["required"] || []

        {
          name: raw_schema[:name],
          description: raw_schema[:description],
          properties: schema_object[:properties] || schema_object["properties"] || {},
          required: required_fields.map(&:to_s),
          type: schema_object[:type] || schema_object["type"] || "object",
          additionalProperties: schema_object[:additionalProperties],
          strict: schema_object[:strict]
        }.compact
      end

      # Get the schema class for direct access
      #
      # @return [Class<RubyLLM::Schema>] The schema class
      def schema_class
        structify_schema
      end

      private

      # Create attr_json fields from the RubyLLM::Schema properties
      def create_attr_json_fields_from_schema
        return unless structify_schema

        schema_hash = structify_schema.new.to_json_schema
        # ruby_llm-schema nests properties under :schema
        schema_object = schema_hash[:schema] || schema_hash["schema"] || schema_hash
        properties = schema_object[:properties] || schema_object["properties"] || {}

        properties.each do |field_name, definition|
          type = map_json_schema_type_to_attr_json(definition[:type] || definition["type"])
          attr_json field_name.to_sym, type
        end
      end

      # Map JSON Schema types to AttrJson types
      def map_json_schema_type_to_attr_json(json_type)
        case json_type.to_s
        when "string" then :string
        when "integer" then :integer
        when "number" then :float
        when "boolean" then :boolean
        when "array", "object" then :json
        else :string
        end
      end
    end
  end
end
