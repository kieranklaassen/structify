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
        name "TestSchema"
        description "A test schema"

        string :title
      end
    end

    schema = test_class.json_schema
    expect(schema[:name]).to eq("TestSchema")
    expect(schema[:description]).to eq("A test schema")
    expect(schema[:required]).to include("title")
    expect(schema[:properties][:title][:type]).to eq("string")
  end
end
