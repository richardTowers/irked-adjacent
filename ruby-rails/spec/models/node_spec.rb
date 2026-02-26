require "rails_helper"

RSpec.describe Node, type: :model do
  describe "validations" do
    it "requires a valid slug format" do
      invalid_slugs = ["Hello", "hello world", "hello--world", "-hello", "hello-", "UPPER", "hello_world"]
      invalid_slugs.each do |bad_slug|
        node = Node.new(slug: bad_slug)
        expect(node).not_to be_valid, "Expected slug '#{bad_slug}' to be invalid"
      end
    end

    it "accepts valid slug formats" do
      valid_slugs = ["hello", "hello-world", "a1-b2-c3", "123"]
      valid_slugs.each do |good_slug|
        node = Node.new(slug: good_slug)
        expect(node).to be_valid, "Expected slug '#{good_slug}' to be valid"
      end
    end

    it "enforces slug uniqueness case-insensitively" do
      Node.create!(slug: "my-slug")
      duplicate = Node.new(slug: "my-slug")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:slug]).to include("has already been taken")
    end

    it "enforces a maximum slug length of 255" do
      node = Node.new(slug: "a" * 256)
      expect(node).not_to be_valid
      expect(node.errors[:slug]).to include("is too long (maximum is 255 characters)")
    end

    it "requires a slug" do
      node = Node.new(slug: nil)
      expect(node).not_to be_valid
      expect(node.errors[:slug]).to include("can't be blank")
    end

    it "preserves an explicitly provided slug" do
      node = Node.new(slug: "custom-slug")
      node.valid?
      expect(node.slug).to eq("custom-slug")
    end
  end

  describe "slug immutability" do
    it "prevents changing the slug after creation" do
      node = Node.create!(slug: "original-slug")
      node.slug = "new-slug"
      expect(node).not_to be_valid
      expect(node.errors[:slug]).to include("cannot be changed after creation")
    end

    it "allows setting the slug on a new record" do
      node = Node.new(slug: "new-slug")
      expect(node).to be_valid
    end
  end

  describe ".create_with_version" do
    it "creates a node and an uncommitted version on main" do
      node, version = Node.create_with_version(title: "Hello World")

      expect(node).to be_persisted
      expect(version).to be_persisted
      expect(version.node).to eq(node)
      expect(version.branch.name).to eq("main")
      expect(version.title).to eq("Hello World")
      expect(version.committed_at).to be_nil
    end

    it "auto-generates a slug from the title" do
      node, _version = Node.create_with_version(title: "Hello World")
      expect(node.slug).to eq("hello-world")
    end

    it "uses an explicitly provided slug" do
      node, _version = Node.create_with_version(title: "Hello World", slug: "custom-slug")
      expect(node.slug).to eq("custom-slug")
    end

    it "stores the body on the version" do
      _node, version = Node.create_with_version(title: "Hello", body: "Some content")
      expect(version.body).to eq("Some content")
    end

    it "rolls back if slug is a duplicate" do
      Node.create!(slug: "taken")
      expect {
        Node.create_with_version(title: "Whatever", slug: "taken")
      }.to raise_error(ActiveRecord::RecordInvalid)
      expect(Version.count).to eq(0)
    end

    it "rolls back if title is blank (version validation fails)" do
      expect {
        Node.create_with_version(title: "")
      }.to raise_error(ActiveRecord::RecordInvalid)
      expect(Node.count).to eq(0)
    end

    it "generates slug from title when title produces valid slug" do
      node, _version = Node.create_with_version(title: "My Great Post")
      expect(node.slug).to eq("my-great-post")
    end

    it "fails when title produces an empty slug" do
      expect {
        Node.create_with_version(title: "!!!")
      }.to raise_error(ActiveRecord::RecordInvalid)
      expect(Node.count).to eq(0)
    end
  end

  describe "associations" do
    it "deleting a node cascades to its versions" do
      node, _version = Node.create_with_version(title: "Doomed")
      expect(Version.count).to eq(1)
      node.destroy
      expect(Version.count).to eq(0)
    end
  end

  describe "slug auto-generation" do
    it "generates a slug from the title via create_with_version" do
      node, _version = Node.create_with_version(title: "Hello World")
      expect(node.slug).to eq("hello-world")
    end

    it "downcases the title" do
      node, _version = Node.create_with_version(title: "UPPERCASE TITLE")
      expect(node.slug).to eq("uppercase-title")
    end

    it "replaces non-alphanumeric characters with hyphens" do
      node, _version = Node.create_with_version(title: "Hello, World! How's it going?")
      expect(node.slug).to eq("hello-world-how-s-it-going")
    end

    it "collapses consecutive hyphens" do
      node, _version = Node.create_with_version(title: "hello---world")
      expect(node.slug).to eq("hello-world")
    end

    it "strips leading and trailing hyphens" do
      node, _version = Node.create_with_version(title: "  Hello World  ")
      expect(node.slug).to eq("hello-world")
    end

    it "does not append numeric suffixes for uniqueness" do
      Node.create_with_version(title: "Hello World")
      expect {
        Node.create_with_version(title: "Hello World")
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "does not overwrite an existing slug" do
      node, _version = Node.create_with_version(title: "New Title", slug: "keep-this")
      expect(node.slug).to eq("keep-this")
    end
  end

  describe "database constraints" do
    it "enforces unique index on slug" do
      Node.create!(slug: "unique-slug")
      duplicate = Node.new(slug: "unique-slug")
      expect {
        duplicate.save(validate: false)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "enforces NOT NULL on slug" do
      node = Node.new
      node.slug = nil
      expect {
        node.save(validate: false)
      }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "auto-manages created_at and updated_at timestamps" do
      node = Node.create!(slug: "test")
      expect(node.created_at).to be_present
      expect(node.updated_at).to be_present
    end
  end
end
