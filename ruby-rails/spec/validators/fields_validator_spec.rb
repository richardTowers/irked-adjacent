require "rails_helper"

RSpec.describe FieldsValidator do
  let(:team) { Team.create!(name: "Test Team") }
  let(:content_type) { ContentType.create!(name: "Article", team: team) }

  def create_field(attrs = {})
    defaults = { content_type: content_type, name: "Field", api_key: "field", field_type: "string", position: 0 }
    FieldDefinition.create!(defaults.merge(attrs))
  end

  def build_node(fields: {})
    Node.new(title: "Test", team: team, content_type: content_type, fields: fields)
  end

  describe "structural validation" do
    it "rejects unknown field keys" do
      create_field(api_key: "title", name: "Title")
      node = build_node(fields: { "title" => "Hello", "unknown_key" => "value" })
      expect(node).not_to be_valid
      expect(node.errors["fields.unknown_key"]).to include("is not a valid field")
    end

    it "allows valid field keys" do
      create_field(api_key: "title", name: "Title")
      node = build_node(fields: { "title" => "Hello" })
      expect(node).to be_valid
    end

    it "allows empty fields when no fields are required" do
      create_field(api_key: "title", name: "Title", required: false)
      node = build_node(fields: {})
      expect(node).to be_valid
    end
  end

  describe "required field validation" do
    before do
      create_field(api_key: "title", name: "Title", required: true)
    end

    it "fails when required field is missing" do
      node = build_node(fields: {})
      expect(node).not_to be_valid
      expect(node.errors["fields.title"]).to include("can't be blank")
    end

    it "fails when required field is nil" do
      node = build_node(fields: { "title" => nil })
      expect(node).not_to be_valid
      expect(node.errors["fields.title"]).to include("can't be blank")
    end

    it "fails when required string field is blank" do
      node = build_node(fields: { "title" => "" })
      expect(node).not_to be_valid
      expect(node.errors["fields.title"]).to include("can't be blank")
    end

    it "passes when required field is present" do
      node = build_node(fields: { "title" => "Hello" })
      expect(node).to be_valid
    end
  end

  describe "string type validation" do
    before do
      create_field(api_key: "name", name: "Name", field_type: "string")
    end

    it "accepts string values" do
      node = build_node(fields: { "name" => "Hello" })
      expect(node).to be_valid
    end

    it "rejects non-string values" do
      node = build_node(fields: { "name" => 123 })
      expect(node).not_to be_valid
      expect(node.errors["fields.name"]).to include("must be a string")
    end
  end

  describe "text type validation" do
    before do
      create_field(api_key: "body", name: "Body", field_type: "text")
    end

    it "accepts string values" do
      node = build_node(fields: { "body" => "Long text content" })
      expect(node).to be_valid
    end

    it "rejects non-string values" do
      node = build_node(fields: { "body" => 42 })
      expect(node).not_to be_valid
      expect(node.errors["fields.body"]).to include("must be a string")
    end
  end

  describe "rich_text type validation" do
    before do
      create_field(api_key: "content", name: "Content", field_type: "rich_text")
    end

    it "accepts string values" do
      node = build_node(fields: { "content" => "<p>Hello</p>" })
      expect(node).to be_valid
    end

    it "rejects non-string values" do
      node = build_node(fields: { "content" => true })
      expect(node).not_to be_valid
      expect(node.errors["fields.content"]).to include("must be a string")
    end
  end

  describe "integer type validation" do
    before do
      create_field(api_key: "count", name: "Count", field_type: "integer")
    end

    it "accepts integer values" do
      node = build_node(fields: { "count" => 42 })
      expect(node).to be_valid
    end

    it "rejects non-integer values" do
      node = build_node(fields: { "count" => 3.14 })
      expect(node).not_to be_valid
      expect(node.errors["fields.count"]).to include("must be an integer")
    end

    it "rejects string values" do
      node = build_node(fields: { "count" => "42" })
      expect(node).not_to be_valid
      expect(node.errors["fields.count"]).to include("must be an integer")
    end
  end

  describe "decimal type validation" do
    before do
      create_field(api_key: "price", name: "Price", field_type: "decimal")
    end

    it "accepts float values" do
      node = build_node(fields: { "price" => 19.99 })
      expect(node).to be_valid
    end

    it "accepts integer values" do
      node = build_node(fields: { "price" => 20 })
      expect(node).to be_valid
    end

    it "rejects non-numeric values" do
      node = build_node(fields: { "price" => "cheap" })
      expect(node).not_to be_valid
      expect(node.errors["fields.price"]).to include("must be a number")
    end
  end

  describe "boolean type validation" do
    before do
      create_field(api_key: "featured", name: "Featured", field_type: "boolean")
    end

    it "accepts true" do
      node = build_node(fields: { "featured" => true })
      expect(node).to be_valid
    end

    it "accepts false" do
      node = build_node(fields: { "featured" => false })
      expect(node).to be_valid
    end

    it "rejects non-boolean values" do
      node = build_node(fields: { "featured" => "yes" })
      expect(node).not_to be_valid
      expect(node.errors["fields.featured"]).to include("must be true or false")
    end

    it "rejects integer values" do
      node = build_node(fields: { "featured" => 1 })
      expect(node).not_to be_valid
      expect(node.errors["fields.featured"]).to include("must be true or false")
    end
  end

  describe "date type validation" do
    before do
      create_field(api_key: "event_date", name: "Event Date", field_type: "date")
    end

    it "accepts valid ISO 8601 date strings" do
      node = build_node(fields: { "event_date" => "2026-03-26" })
      expect(node).to be_valid
    end

    it "rejects invalid date strings" do
      node = build_node(fields: { "event_date" => "not-a-date" })
      expect(node).not_to be_valid
      expect(node.errors["fields.event_date"]).to include("must be a valid date in ISO 8601 format (YYYY-MM-DD)")
    end

    it "rejects non-string values" do
      node = build_node(fields: { "event_date" => 20260326 })
      expect(node).not_to be_valid
      expect(node.errors["fields.event_date"]).to include("must be a string in ISO 8601 date format (YYYY-MM-DD)")
    end

    it "rejects invalid calendar dates" do
      node = build_node(fields: { "event_date" => "2026-02-30" })
      expect(node).not_to be_valid
      expect(node.errors["fields.event_date"]).to include("must be a valid date in ISO 8601 format (YYYY-MM-DD)")
    end
  end

  describe "datetime type validation" do
    before do
      create_field(api_key: "starts_at", name: "Starts At", field_type: "datetime")
    end

    it "accepts valid ISO 8601 datetime strings" do
      node = build_node(fields: { "starts_at" => "2026-03-26T10:00:00Z" })
      expect(node).to be_valid
    end

    it "accepts datetime with timezone offset" do
      node = build_node(fields: { "starts_at" => "2026-03-26T10:00:00+05:00" })
      expect(node).to be_valid
    end

    it "rejects invalid datetime strings" do
      node = build_node(fields: { "starts_at" => "not-a-datetime" })
      expect(node).not_to be_valid
      expect(node.errors["fields.starts_at"]).to include("must be a valid datetime in ISO 8601 format")
    end

    it "rejects non-string values" do
      node = build_node(fields: { "starts_at" => 12345 })
      expect(node).not_to be_valid
      expect(node.errors["fields.starts_at"]).to include("must be a string in ISO 8601 datetime format")
    end
  end

  describe "reference type validation" do
    let(:referenced_ct) { ContentType.create!(name: "Author", team: team) }
    let!(:referenced_node) { Node.create!(title: "Author 1", team: team, content_type: referenced_ct) }

    before do
      create_field(api_key: "author", name: "Author", field_type: "reference")
    end

    it "accepts a valid node ID" do
      node = build_node(fields: { "author" => referenced_node.id })
      expect(node).to be_valid
    end

    it "rejects non-integer values" do
      node = build_node(fields: { "author" => "not-an-id" })
      expect(node).not_to be_valid
      expect(node.errors["fields.author"]).to include("must be an integer")
    end

    it "rejects non-existent node IDs" do
      node = build_node(fields: { "author" => 999999 })
      expect(node).not_to be_valid
      expect(node.errors["fields.author"]).to include("references a node that does not exist")
    end
  end

  describe "reference type with allowed_content_types" do
    let(:author_ct) { ContentType.create!(name: "Author", team: team) }
    let(:category_ct) { ContentType.create!(name: "Category", team: team) }
    let!(:author_node) { Node.create!(title: "Author 1", team: team, content_type: author_ct) }
    let!(:category_node) { Node.create!(title: "Category 1", team: team, content_type: category_ct) }

    before do
      create_field(
        api_key: "author",
        name: "Author",
        field_type: "reference",
        validations: { "allowed_content_types" => [author_ct.id] }
      )
    end

    it "accepts a reference to a node with an allowed content type" do
      node = build_node(fields: { "author" => author_node.id })
      expect(node).to be_valid
    end

    it "rejects a reference to a node with a disallowed content type" do
      node = build_node(fields: { "author" => category_node.id })
      expect(node).not_to be_valid
      expect(node.errors["fields.author"]).to include("references a node with a disallowed content type")
    end
  end

  describe "string min_length / max_length validations" do
    before do
      create_field(
        api_key: "name",
        name: "Name",
        field_type: "string",
        validations: { "min_length" => 3, "max_length" => 10 }
      )
    end

    it "accepts strings within length bounds" do
      node = build_node(fields: { "name" => "Hello" })
      expect(node).to be_valid
    end

    it "rejects strings shorter than min_length" do
      node = build_node(fields: { "name" => "Hi" })
      expect(node).not_to be_valid
      expect(node.errors["fields.name"]).to include("is too short (minimum is 3 characters)")
    end

    it "rejects strings longer than max_length" do
      node = build_node(fields: { "name" => "a" * 11 })
      expect(node).not_to be_valid
      expect(node.errors["fields.name"]).to include("is too long (maximum is 10 characters)")
    end
  end

  describe "numeric min / max validations" do
    context "integer field" do
      before do
        create_field(
          api_key: "max_attendees",
          name: "Max Attendees",
          field_type: "integer",
          validations: { "min" => 1, "max" => 1000 }
        )
      end

      it "accepts values within range" do
        node = build_node(fields: { "max_attendees" => 50 })
        expect(node).to be_valid
      end

      it "rejects values below min" do
        node = build_node(fields: { "max_attendees" => 0 })
        expect(node).not_to be_valid
        expect(node.errors["fields.max_attendees"]).to include("must be greater than or equal to 1")
      end

      it "rejects values above max" do
        node = build_node(fields: { "max_attendees" => 1001 })
        expect(node).not_to be_valid
        expect(node.errors["fields.max_attendees"]).to include("must be less than or equal to 1000")
      end
    end

    context "decimal field" do
      before do
        create_field(
          api_key: "price",
          name: "Price",
          field_type: "decimal",
          validations: { "min" => 0.01, "max" => 99.99 }
        )
      end

      it "accepts values within range" do
        node = build_node(fields: { "price" => 19.99 })
        expect(node).to be_valid
      end

      it "rejects values below min" do
        node = build_node(fields: { "price" => 0.001 })
        expect(node).not_to be_valid
        expect(node.errors["fields.price"]).to include("must be greater than or equal to 0.01")
      end

      it "rejects values above max" do
        node = build_node(fields: { "price" => 100.00 })
        expect(node).not_to be_valid
        expect(node.errors["fields.price"]).to include("must be less than or equal to 99.99")
      end
    end
  end

  describe "error key format" do
    before do
      create_field(api_key: "event_date", name: "Event Date", field_type: "date", required: true)
      create_field(api_key: "max_attendees", name: "Max Attendees", field_type: "integer", position: 1, validations: { "min" => 1 })
    end

    it "keys errors by fields.api_key" do
      node = build_node(fields: { "max_attendees" => 0 })
      node.valid?

      expect(node.errors["fields.event_date"]).to include("can't be blank")
      expect(node.errors["fields.max_attendees"]).to include("must be greater than or equal to 1")
    end
  end
end
