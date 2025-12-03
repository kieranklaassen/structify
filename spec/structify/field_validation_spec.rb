# frozen_string_literal: true

require "spec_helper"

RSpec.describe Structify::FieldValidation do
  # Create a test model class that includes our module
  let(:model_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "articles"
      include Structify::Model
    end
  end

  # Set up our test database
  before(:all) do
    ActiveRecord::Schema.define do
      create_table :articles, force: true do |t|
        t.string :title
        t.text :content
        t.json :json_attributes
        t.timestamps
      end
    end
  end

  describe "always-on validation" do
    context "with basic field types" do
      before do
        model_class.schema_definition do
          name "BasicValidation"

          string :title
          integer :count, required: false
          number :price, required: false
          boolean :active, required: false
          string :category, enum: ["tech", "business", "science"], required: false
        end
      end

      describe "required field validation" do
        it "raises RequiredFieldError when required field is missing" do
          instance = model_class.new

          expect {
            instance.save!
          }.to raise_error(Structify::RequiredFieldError) do |error|
            expect(error.field_name).to eq(:title)
            expect(error.message).to include("Required field 'title' is missing")
          end
        end

        it "raises RequiredFieldError when required field is nil" do
          instance = model_class.new(title: nil)

          expect {
            instance.save!
          }.to raise_error(Structify::RequiredFieldError) do |error|
            expect(error.field_name).to eq(:title)
          end
        end

        it "raises RequiredFieldError when required field is empty string" do
          instance = model_class.new(title: "")

          expect {
            instance.save!
          }.to raise_error(Structify::RequiredFieldError) do |error|
            expect(error.field_name).to eq(:title)
          end
        end

        it "allows valid required field" do
          instance = model_class.new(title: "Valid Title")

          expect {
            instance.save!
          }.not_to raise_error
        end
      end

      describe "type validation" do
        it "raises TypeMismatchError for wrong type" do
          instance = model_class.new(title: "Valid", count: "not an integer")

          # AttrJson will try to coerce, but if it can't, the type will be wrong
          # For this test, we need to bypass AttrJson coercion
          instance.instance_variable_set(:@attributes, instance.instance_variable_get(:@attributes))

          # Direct assignment that bypasses coercion
          allow(instance).to receive(:count).and_return("not an integer")

          expect {
            instance.valid?
          }.to raise_error(Structify::TypeMismatchError)
        end

        it "allows valid type assignments" do
          instance = model_class.new(
            title: "Valid Title",
            count: 42,
            price: 19.99,
            active: true
          )

          expect {
            instance.save!
          }.not_to raise_error
        end
      end

      describe "enum validation" do
        it "raises EnumValidationError for invalid enum value" do
          instance = model_class.new(title: "Valid", category: "invalid")

          expect {
            instance.save!
          }.to raise_error(Structify::EnumValidationError) do |error|
            expect(error.field_name).to eq(:category)
            expect(error.value).to eq("invalid")
            expect(error.allowed_values).to eq(["tech", "business", "science"])
          end
        end

        it "allows valid enum value" do
          instance = model_class.new(title: "Valid", category: "tech")

          expect {
            instance.save!
          }.not_to raise_error
        end

        it "allows nil for optional enum field" do
          instance = model_class.new(title: "Valid", category: nil)

          expect {
            instance.save!
          }.not_to raise_error
        end
      end
    end

    context "with array fields" do
      before do
        model_class.schema_definition do
          name "ArrayValidation"

          string :title
          array :tags, of: :string, min_items: 1, max_items: 5, required: false
        end
      end

      describe "array constraint validation" do
        it "raises ArrayConstraintError when array has too few items" do
          instance = model_class.new(title: "Valid", tags: [])

          expect {
            instance.save!
          }.to raise_error(Structify::ArrayConstraintError) do |error|
            expect(error.field_name).to eq(:tags)
            expect(error.message).to include("at least 1 items")
          end
        end

        it "raises ArrayConstraintError when array has too many items" do
          instance = model_class.new(title: "Valid", tags: ["a", "b", "c", "d", "e", "f"])

          expect {
            instance.save!
          }.to raise_error(Structify::ArrayConstraintError) do |error|
            expect(error.field_name).to eq(:tags)
            expect(error.message).to include("at most 5 items")
          end
        end

        it "allows valid array" do
          instance = model_class.new(title: "Valid", tags: ["ruby", "rails"])

          expect {
            instance.save!
          }.not_to raise_error
        end
      end

      describe "array item type validation" do
        it "raises ArrayConstraintError when item has wrong type" do
          instance = model_class.new(title: "Valid", tags: ["valid", 123])

          expect {
            instance.save!
          }.to raise_error(Structify::ArrayConstraintError) do |error|
            expect(error.message).to include("expected string")
          end
        end
      end
    end

    context "with object fields" do
      before do
        model_class.schema_definition do
          name "ObjectValidation"

          string :title
          object :author, required: false do
            string :name
            string :email, required: false
          end
        end
      end

      describe "object property validation" do
        it "raises ObjectValidationError when required property is missing" do
          instance = model_class.new(title: "Valid", author: { "email" => "test@example.com" })

          expect {
            instance.save!
          }.to raise_error(Structify::ObjectValidationError) do |error|
            expect(error.field_name).to eq(:author)
            expect(error.property_name).to eq("name")
            expect(error.message).to include("required property is missing")
          end
        end

        it "allows valid object with all required properties" do
          instance = model_class.new(
            title: "Valid",
            author: { "name" => "John Doe", "email" => "john@example.com" }
          )

          expect {
            instance.save!
          }.not_to raise_error
        end

        it "allows valid object with only required properties" do
          instance = model_class.new(
            title: "Valid",
            author: { "name" => "John Doe" }
          )

          expect {
            instance.save!
          }.not_to raise_error
        end
      end

      describe "object property type validation" do
        it "raises ObjectValidationError when property has wrong type" do
          instance = model_class.new(
            title: "Valid",
            author: { "name" => 123 }
          )

          expect {
            instance.save!
          }.to raise_error(Structify::ObjectValidationError) do |error|
            expect(error.message).to include("expected string")
          end
        end
      end
    end

    context "with nested arrays of objects" do
      before do
        model_class.schema_definition do
          name "NestedValidation"

          string :title
          array :sections, required: false do
            object do
              string :heading
              string :content, required: false
            end
          end
        end
      end

      it "validates objects within arrays" do
        instance = model_class.new(
          title: "Valid",
          sections: [
            { "heading" => "Section 1", "content" => "Content 1" },
            { "content" => "Missing heading" }  # Missing required heading
          ]
        )

        expect {
          instance.save!
        }.to raise_error(Structify::ArrayConstraintError) do |error|
          expect(error.message).to include("missing required property")
          expect(error.message).to include("heading")
        end
      end

      it "allows valid nested arrays of objects" do
        instance = model_class.new(
          title: "Valid",
          sections: [
            { "heading" => "Section 1", "content" => "Content 1" },
            { "heading" => "Section 2" }
          ]
        )

        expect {
          instance.save!
        }.not_to raise_error
      end
    end
  end

  describe "error attributes" do
    before do
      model_class.schema_definition do
        name "ErrorAttributes"
        string :title
      end
    end

    it "includes record reference in error" do
      instance = model_class.new

      begin
        instance.save!
      rescue Structify::RequiredFieldError => e
        expect(e.record).to eq(instance)
      end
    end
  end
end
