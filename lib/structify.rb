# frozen_string_literal: true

require_relative "structify/version"
require_relative "structify/schema_serializer"
require_relative "structify/model"

# Structify is a DSL for defining extraction schemas for LLM-powered models.
# It provides a simple way to integrate with Rails models for LLM extraction,
# including versioning, assistant prompts, and more.
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
module Structify
  class Error < StandardError; end
end
