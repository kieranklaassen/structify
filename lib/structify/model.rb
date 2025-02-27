# frozen_string_literal: true

require "active_support/concern"
require "active_support/core_ext/class/attribute"
require "attr_json"
require_relative "schema_serializer"

module Structify
  # The Model module provides a DSL for defining LLM extraction schemas in your Rails models.
  # It allows you to define fields, versioning, and assistant prompts for LLM-based data extraction.
  #
  # @example
  #   class Article < ApplicationRecord
  #     include Structify::Model
  #
  #     schema_definition do
  #       title "Article Extraction"
  #       description "Extract article metadata"
  #       version 1
  #       assistant_prompt "Extract the following fields from the article"
  #       llm_model "gpt-4"
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

      # Get the assistant prompt
      #
      # @return [String] The assistant prompt
      def extraction_assistant_prompt
        schema_builder&.assistant_prompt_str
      end

      # Get the LLM model name
      #
      # @return [String] The model name
      def extraction_llm_model
        schema_builder&.model_name
      end
    end
  end

  # Builder class for constructing the schema
  class SchemaBuilder
    # @return [Class] The model class
    # @return [Array<Hash>] The field definitions
    # @return [String] The schema title
    # @return [String] The schema description
    # @return [String] The assistant prompt
    # @return [String] The LLM model name
    # @return [Integer] The schema version
    attr_reader :model, :fields, :title_str, :description_str,
                :assistant_prompt_str, :model_name, :version_number

    # Initialize a new SchemaBuilder
    #
    # @param model [Class] The model class
    def initialize(model)
      @model = model
      @fields = []
      @assistant_prompt_str = nil
      @model_name = nil
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

    # Set the assistant prompt
    #
    # @param prompt [String] The prompt text
    # @return [void]
    def assistant_prompt(prompt)
      @assistant_prompt_str = prompt.strip
    end

    # Set the LLM model name
    #
    # @param name [String] The model name
    # @return [void]
    def llm_model(name)
      @model_name = name
    end

    # Define a field in the schema
    #
    # @param name [Symbol] The field name
    # @param type [Symbol] The field type
    # @param required [Boolean] Whether the field is required
    # @param description [String] The field description
    # @param enum [Array] Possible values for the field
    # @return [void]
    def field(name, type, required: false, description: nil, enum: nil)
      fields << {
        name: name,
        type: type,
        required: required,
        description: description,
        enum: enum
      }

      model.attr_json name, type
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