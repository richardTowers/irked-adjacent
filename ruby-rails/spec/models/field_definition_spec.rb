require 'rails_helper'

RSpec.describe FieldDefinition, type: :model do
  let(:team) { Team.create!(name: "Test Team") }
  let(:content_type) { ContentType.create!(name: "Blog Post", team: team) }

  def build_field(**attrs)
    FieldDefinition.new({
      content_type: content_type,
      name: "Title",
      api_key: "title",
      field_type: "string",
      position: 0
    }.merge(attrs))
  end

  describe "validations" do
    it "is valid with all required attributes" do
      field = build_field
      expect(field).to be_valid
    end

    it "requires a name" do
      field = build_field(name: nil)
      expect(field).not_to be_valid
      expect(field.errors[:name]).to include("can't be blank")
    end

    it "enforces a maximum name length of 255" do
      field = build_field(name: "a" * 256)
      expect(field).not_to be_valid
      expect(field.errors[:name]).to include("is too long (maximum is 255 characters)")
    end

    it "requires an api_key" do
      field = build_field(api_key: nil)
      expect(field).not_to be_valid
      expect(field.errors[:api_key]).to include("can't be blank")
    end

    it "enforces a maximum api_key length of 255" do
      field = build_field(api_key: "a" * 256)
      expect(field).not_to be_valid
      expect(field.errors[:api_key]).to include("is too long (maximum is 255 characters)")
    end

    it "rejects api_key starting with a digit" do
      field = build_field(api_key: "1title")
      expect(field).not_to be_valid
      expect(field.errors[:api_key]).to be_present
    end

    it "rejects api_key containing uppercase letters" do
      field = build_field(api_key: "Title")
      expect(field).not_to be_valid
      expect(field.errors[:api_key]).to be_present
    end

    it "rejects api_key containing hyphens" do
      field = build_field(api_key: "my-field")
      expect(field).not_to be_valid
      expect(field.errors[:api_key]).to be_present
    end

    it "accepts valid api_key formats" do
      %w[title event_date a1 field_1_name].each do |key|
        field = build_field(api_key: key)
        expect(field).to be_valid, "Expected api_key '#{key}' to be valid"
      end
    end

    it "enforces api_key uniqueness within a content type" do
      build_field(api_key: "title").save!
      duplicate = build_field(api_key: "title")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:api_key]).to include("has already been taken")
    end

    it "allows the same api_key on different content types" do
      other_content_type = ContentType.create!(name: "Event", team: team)
      build_field(api_key: "title").save!
      field = build_field(api_key: "title", content_type: other_content_type)
      expect(field).to be_valid
    end

    it "requires a field_type" do
      field = build_field(field_type: nil)
      expect(field).not_to be_valid
      expect(field.errors[:field_type]).to be_present
    end

    it "rejects invalid field_type values" do
      field = build_field(field_type: "invalid")
      expect(field).not_to be_valid
      expect(field.errors[:field_type]).to include("is not included in the list")
    end

    FieldDefinition::FIELD_TYPES.each do |type|
      it "accepts field_type '#{type}'" do
        field = build_field(field_type: type, api_key: "field_#{type}")
        expect(field).to be_valid
      end
    end

    it "requires a content_type" do
      field = build_field(content_type: nil)
      expect(field).not_to be_valid
      expect(field.errors[:content_type]).to include("must exist")
    end

    it "requires position to be a non-negative integer" do
      field = build_field(position: -1)
      expect(field).not_to be_valid
      expect(field.errors[:position]).to be_present
    end

    it "accepts position of zero" do
      field = build_field(position: 0)
      expect(field).to be_valid
    end
  end

  describe "validations JSON" do
    it "accepts valid validation keys for string fields" do
      field = build_field(field_type: "string", validations: { "min_length" => 1, "max_length" => 100 })
      expect(field).to be_valid
    end

    it "accepts valid validation keys for text fields" do
      field = build_field(field_type: "text", api_key: "body", validations: { "min_length" => 10 })
      expect(field).to be_valid
    end

    it "accepts valid validation keys for rich_text fields" do
      field = build_field(field_type: "rich_text", api_key: "content", validations: { "max_length" => 5000 })
      expect(field).to be_valid
    end

    it "accepts valid validation keys for integer fields" do
      field = build_field(field_type: "integer", api_key: "count", validations: { "min" => 0, "max" => 100 })
      expect(field).to be_valid
    end

    it "accepts valid validation keys for decimal fields" do
      field = build_field(field_type: "decimal", api_key: "price", validations: { "min" => 0.0, "max" => 999.99 })
      expect(field).to be_valid
    end

    it "accepts nil validations for boolean fields" do
      field = build_field(field_type: "boolean", api_key: "active", validations: nil)
      expect(field).to be_valid
    end

    it "accepts valid validation keys for reference fields" do
      field = build_field(field_type: "reference", api_key: "author", validations: { "allowed_content_types" => [1, 2] })
      expect(field).to be_valid
    end

    it "rejects unknown validation keys for a string field" do
      field = build_field(field_type: "string", validations: { "unknown_key" => true })
      expect(field).not_to be_valid
      expect(field.errors[:validations]).to be_present
    end

    it "rejects unknown validation keys for a boolean field" do
      field = build_field(field_type: "boolean", api_key: "active", validations: { "min" => 0 })
      expect(field).not_to be_valid
      expect(field.errors[:validations]).to be_present
    end

    it "rejects unknown validation keys for a reference field" do
      field = build_field(field_type: "reference", api_key: "author", validations: { "min_length" => 1 })
      expect(field).not_to be_valid
      expect(field.errors[:validations]).to be_present
    end

    it "accepts empty validations" do
      field = build_field(validations: {})
      expect(field).to be_valid
    end

    it "accepts nil validations" do
      field = build_field(validations: nil)
      expect(field).to be_valid
    end
  end

  describe "associations" do
    it "belongs to a content type" do
      field = build_field
      field.save!
      expect(field.content_type).to eq(content_type)
    end

    it "is destroyed when its content type is destroyed" do
      field = build_field
      field.save!
      expect { content_type.destroy }.to change(FieldDefinition, :count).by(-1)
    end

    it "field definitions are ordered by position" do
      build_field(name: "Third", api_key: "third", position: 2).save!
      build_field(name: "First", api_key: "first", position: 0).save!
      build_field(name: "Second", api_key: "second", position: 1).save!

      expect(content_type.field_definitions.pluck(:api_key)).to eq(%w[first second third])
    end
  end

  describe "database constraints" do
    it "enforces compound unique index on content_type_id and api_key" do
      build_field(api_key: "title").save!
      duplicate = build_field(api_key: "title")
      expect {
        duplicate.save(validate: false)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "enforces foreign key on content_type_id" do
      field = build_field(content_type_id: 999999)
      expect {
        field.save(validate: false)
      }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "enforces NOT NULL on name" do
      field = build_field(name: nil)
      expect {
        field.save(validate: false)
      }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "enforces NOT NULL on api_key" do
      field = build_field(api_key: nil)
      expect {
        field.save(validate: false)
      }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "enforces NOT NULL on field_type" do
      field = build_field(field_type: nil)
      expect {
        field.save(validate: false)
      }.to raise_error(ActiveRecord::NotNullViolation)
    end
  end

  describe "timestamps" do
    it "sets created_at and updated_at automatically" do
      field = build_field
      field.save!
      expect(field.created_at).to be_present
      expect(field.updated_at).to be_present
    end
  end

  describe "defaults" do
    it "defaults required to false" do
      field = build_field
      field.save!
      expect(field.required).to be false
    end

    it "defaults position to 0" do
      field = FieldDefinition.new(content_type: content_type, name: "Title", api_key: "title", field_type: "string")
      field.save!
      expect(field.position).to eq(0)
    end
  end
end
