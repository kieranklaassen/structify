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
          version 1
          
          field :title, :string, required: true
          field :count, :integer
          field :price, :number
          field :active, :boolean
          field :category, :string, enum: ["tech", "business", "science"]
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

      describe "type validation with AttrJson coercion" do
        it "allows AttrJson type coercion for valid coercible values" do
          # AttrJson automatically coerces "123" to 123, "true" to true, etc.
          instance = model_class.new(
            title: "Valid Title",
            count: "123",    # String that converts to integer
            active: "true"   # String that converts to boolean
          )
          
          expect {
            instance.save!
          }.not_to raise_error
          
          expect(instance.count).to eq(123)
          expect(instance.active).to eq(true)
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
          instance = model_class.new(title: "Valid Title", category: "invalid")
          
          expect {
            instance.save!
          }.to raise_error(Structify::EnumValidationError) do |error|
            expect(error.field_name).to eq(:category)
            expect(error.value).to eq("invalid")
            expect(error.allowed_values).to eq(["tech", "business", "science"])
          end
        end

        it "allows valid enum value" do
          instance = model_class.new(title: "Valid Title", category: "tech")
          
          expect {
            instance.save!
          }.not_to raise_error
        end

        it "allows nil for optional enum field" do
          instance = model_class.new(title: "Valid Title", category: nil)
          
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
          version 1
          
          field :title, :string, required: true
          field :tags, :array, items: { type: "string" }
          field :scores, :array, items: { type: "integer" }, min_items: 1, max_items: 5
          field :unique_tags, :array, items: { type: "string" }, unique_items: true
        end
      end

      describe "array type validation" do
        it "raises TypeMismatchError when array field gets string" do
          instance = model_class.new(title: "Valid Title", tags: "not an array")
          
          expect {
            instance.save!
          }.to raise_error(Structify::TypeMismatchError) do |error|
            expect(error.field_name).to eq(:tags)
            expect(error.expected_type).to eq(:array)
            expect(error.actual_type).to eq("string")
            expect(error.value).to eq("not an array")
          end
        end

        it "allows valid array" do
          instance = model_class.new(title: "Valid Title", tags: ["ruby", "rails"])
          
          expect {
            instance.save!
          }.not_to raise_error
        end
      end

      describe "array constraint validation" do
        it "raises ArrayConstraintError for min_items violation" do
          instance = model_class.new(title: "Valid Title", scores: [])
          
          expect {
            instance.save!
          }.to raise_error(Structify::ArrayConstraintError) do |error|
            expect(error.field_name).to eq(:scores)
            expect(error.message).to include("must have at least 1 items")
          end
        end

        it "raises ArrayConstraintError for max_items violation" do
          instance = model_class.new(title: "Valid Title", scores: [1, 2, 3, 4, 5, 6])
          
          expect {
            instance.save!
          }.to raise_error(Structify::ArrayConstraintError) do |error|
            expect(error.field_name).to eq(:scores)
            expect(error.message).to include("must have at most 5 items")
          end
        end

        it "raises ArrayConstraintError for unique_items violation" do
          instance = model_class.new(title: "Valid Title", unique_tags: ["ruby", "ruby"])
          
          expect {
            instance.save!
          }.to raise_error(Structify::ArrayConstraintError) do |error|
            expect(error.field_name).to eq(:unique_tags)
            expect(error.message).to include("items must be unique")
          end
        end

        it "allows valid array constraints" do
          instance = model_class.new(
            title: "Valid Title",
            scores: [1, 2, 3],
            unique_tags: ["ruby", "rails", "javascript"]
          )
          
          expect {
            instance.save!
          }.not_to raise_error
        end
      end

      describe "array item type validation" do
        it "raises ArrayConstraintError for invalid item type" do
          instance = model_class.new(title: "Valid Title", tags: ["valid", 123])
          
          expect {
            instance.save!
          }.to raise_error(Structify::ArrayConstraintError) do |error|
            expect(error.field_name).to eq(:tags)
            expect(error.message).to include("item at index 1 expected string, got integer")
          end
        end

        it "allows valid item types" do
          instance = model_class.new(title: "Valid Title", tags: ["ruby", "rails"])
          
          expect {
            instance.save!
          }.not_to raise_error
        end
      end
    end

    context "with object fields" do
      before do
        model_class.schema_definition do
          name "ObjectValidation"
          version 1
          
          field :title, :string, required: true
          field :author, :object, required: true, properties: {
            "name" => { type: "string", required: true },
            "email" => { type: "string" },
            "age" => { type: "integer" }
          }
          field :metadata, :object, properties: {
            "category" => { type: "string", enum: ["tech", "business"] },
            "published" => { type: "boolean" }
          }
        end
      end

      describe "object type validation" do
        it "raises TypeMismatchError when object field gets string" do
          instance = model_class.new(title: "Valid Title", author: "not an object")
          
          expect {
            instance.save!
          }.to raise_error(Structify::TypeMismatchError) do |error|
            expect(error.field_name).to eq(:author)
            expect(error.expected_type).to eq(:object)
            expect(error.actual_type).to eq("string")
          end
        end

        it "allows valid object" do
          instance = model_class.new(
            title: "Valid Title",
            author: { "name" => "John Doe", "email" => "john@example.com" }
          )
          
          expect {
            instance.save!
          }.not_to raise_error
        end
      end

      describe "object property validation" do
        it "raises ObjectValidationError for missing required property" do
          instance = model_class.new(
            title: "Valid Title",
            author: { "email" => "john@example.com" }  # Missing required "name"
          )
          
          expect {
            instance.save!
          }.to raise_error(Structify::ObjectValidationError) do |error|
            expect(error.field_name).to eq(:author)
            expect(error.property_name).to eq("name")
            expect(error.message).to include("required property is missing")
          end
        end

        it "raises ObjectValidationError for invalid property type" do
          instance = model_class.new(
            title: "Valid Title",
            author: { "name" => "John Doe", "age" => "thirty" }  # Age should be integer
          )
          
          expect {
            instance.save!
          }.to raise_error(Structify::ObjectValidationError) do |error|
            expect(error.field_name).to eq(:author)
            expect(error.property_name).to eq("age")
            expect(error.message).to include("expected integer, got string")
          end
        end

        it "raises ObjectValidationError for invalid property enum" do
          instance = model_class.new(
            title: "Valid Title",
            author: { "name" => "John Doe" },
            metadata: { "category" => "sports" }  # Invalid enum value
          )
          
          expect {
            instance.save!
          }.to raise_error(Structify::ObjectValidationError) do |error|
            expect(error.field_name).to eq(:metadata)
            expect(error.property_name).to eq("category")
            expect(error.message).to include("not in allowed values")
          end
        end

        it "allows valid object properties" do
          instance = model_class.new(
            title: "Valid Title",
            author: { "name" => "John Doe", "email" => "john@example.com", "age" => 30 },
            metadata: { "category" => "tech", "published" => true }
          )
          
          expect {
            instance.save!
          }.not_to raise_error
        end
      end
    end

    context "with complex nested structures" do
      before do
        model_class.schema_definition do
          name "ComplexValidation"
          version 1
          
          field :title, :string, required: true
          field :activities, :array, items: {
            type: "object",
            properties: {
              "title" => { type: "string", required: true },
              "summary" => { type: "string", required: true },
              "impact" => { type: "integer", required: true }
            }
          }
        end
      end

      it "validates the exact scenario from issue #3 - string instead of array" do
        instance = model_class.new(title: "Valid Title", activities: "123")
        
        expect {
          instance.save!
        }.to raise_error(Structify::TypeMismatchError) do |error|
          expect(error.field_name).to eq(:activities)
          expect(error.expected_type).to eq(:array)
          expect(error.actual_type).to eq("string")
          expect(error.value).to eq("123")
        end
      end

      it "validates the exact scenario from issue #3 - invalid object structure" do
        instance = model_class.new(title: "Valid Title", activities: [{ bad_attr: 1 }])
        
        expect {
          instance.save!
        }.to raise_error(Structify::ArrayConstraintError) do |error|
          expect(error.field_name).to eq(:activities)
          expect(error.message).to include("item at index 0 is missing required property 'title'")
        end
      end

      it "allows valid complex nested structure" do
        instance = model_class.new(
          title: "Valid Title",
          activities: [
            {
              "title" => "Infrastructure Development",
              "summary" => "Built new roads and bridges",
              "impact" => 4
            },
            {
              "title" => "Education Reform",
              "summary" => "Improved school curriculum",
              "impact" => 5
            }
          ]
        )
        
        expect {
          instance.save!
        }.not_to raise_error
      end

      it "validates array item object property types" do
        instance = model_class.new(
          title: "Valid Title",
          activities: [
            {
              "title" => "Valid Activity",
              "summary" => "Valid summary",
              "impact" => "not an integer"  # Invalid type
            }
          ]
        )
        
        expect {
          instance.save!
        }.to raise_error(Structify::ArrayConstraintError) do |error|
          expect(error.field_name).to eq(:activities)
          expect(error.message).to include("item at index 0 property 'impact' expected integer, got string")
        end
      end
    end

    context "with version constraints" do
      let(:v1_class) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "articles"
          include Structify::Model

          schema_definition do
            version 1
            name "VersionedValidation"
            
            field :title, :string, required: true
            field :old_field, :string, versions: 1
          end
        end
      end

      let(:v2_class) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "articles"
          include Structify::Model

          schema_definition do
            version 2
            name "VersionedValidation"
            
            field :title, :string, required: true, versions: 1..999
            field :old_field, :string, versions: 1
            field :new_field, :string, versions: 2..999
          end
        end
      end

      it "validates fields available in current version" do
        instance = v1_class.new(title: "Valid Title", old_field: "Valid")
        
        expect {
          instance.save!
        }.not_to raise_error
      end

      it "skips validation for fields not available in record version" do
        # Create v1 record
        v1_record = v1_class.create!(title: "Valid Title", old_field: "Valid")
        
        # Access with v2 schema - should not validate new_field since record is v1
        v2_record = v2_class.find(v1_record.id)
        
        expect {
          v2_record.save!
        }.not_to raise_error
      end
    end

    context "error attributes and context" do
      before do
        model_class.schema_definition do
          name "ErrorContextValidation"
          version 1
          
          field :title, :string, required: true
          field :category, :string, enum: ["tech", "business"]
        end
      end

      it "includes record reference in exception" do
        instance = model_class.new
        
        expect {
          instance.save!
        }.to raise_error(Structify::RequiredFieldError) do |error|
          expect(error.record).to eq(instance)
        end
      end

      it "includes field name and value in exception" do
        instance = model_class.new(title: "Valid Title", category: "invalid")
        
        expect {
          instance.save!
        }.to raise_error(Structify::EnumValidationError) do |error|
          expect(error.field_name).to eq(:category)
          expect(error.value).to eq("invalid")
          expect(error.allowed_values).to eq(["tech", "business"])
        end
      end
    end
  end

  describe "validation inheritance" do
    it "includes FieldValidation module automatically" do
      expect(model_class.included_modules).to include(Structify::FieldValidation)
    end

    it "sets up validation callback" do
      expect(model_class._validate_callbacks.map(&:filter)).to include(:validate_structify_fields)
    end
  end
end