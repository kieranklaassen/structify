# frozen_string_literal: true

require "spec_helper"

RSpec.describe Structify do
  it "has a version number" do
    expect(Structify::VERSION).not_to be nil
  end

  it "provides a DSL for defining LLM extraction schemas" do
    test_class = Class.new(ActiveRecord::Base) do
      self.table_name = "articles"
      include Structify::Model

      schema_definition do
        title "Test Schema"
        description "A test schema"
        version 1
        assistant_prompt "Test prompt"
        llm_model "gpt-4"

        field :title, :string, required: true
      end
    end

    expect(test_class.json_schema).to include(
      name: "Test Schema",
      description: "A test schema",
      parameters: {
        type: "object",
        required: ["title"],
        properties: {
          "title" => { type: "string" }
        }
      }
    )
  end
end
