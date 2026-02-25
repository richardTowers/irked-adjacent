require 'rails_helper'

RSpec.describe Node, type: :model do
  describe "validations" do
    it "is valid with a title and auto-generated slug" do
      node = Node.new(title: "Hello World")
      expect(node).to be_valid
    end

    it "requires a title" do
      node = Node.new(title: nil)
      expect(node).not_to be_valid
      expect(node.errors[:title]).to include("can't be blank")
    end

    it "enforces a maximum title length of 255" do
      node = Node.new(title: "a" * 256)
      expect(node).not_to be_valid
      expect(node.errors[:title]).to include("is too long (maximum is 255 characters)")
    end

    it "accepts a title of exactly 255 characters" do
      node = Node.new(title: "a" * 255)
      expect(node).to be_valid
    end

    it "requires a valid slug format" do
      invalid_slugs = ["Hello", "hello world", "hello--world", "-hello", "hello-", "UPPER", "hello_world"]
      invalid_slugs.each do |bad_slug|
        node = Node.new(title: "Something", slug: bad_slug)
        expect(node).not_to be_valid, "Expected slug '#{bad_slug}' to be invalid"
      end
    end

    it "accepts valid slug formats" do
      valid_slugs = ["hello", "hello-world", "a1-b2-c3", "123"]
      valid_slugs.each do |good_slug|
        node = Node.new(title: "Something", slug: good_slug)
        expect(node).to be_valid, "Expected slug '#{good_slug}' to be valid"
      end
    end

    it "enforces slug uniqueness case-insensitively" do
      Node.create!(title: "First", slug: "my-slug")
      duplicate = Node.new(title: "Second", slug: "my-slug")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:slug]).to include("has already been taken")
    end

    it "enforces a maximum slug length of 255" do
      node = Node.new(title: "Something", slug: "a" * 256)
      expect(node).not_to be_valid
      expect(node.errors[:slug]).to include("is too long (maximum is 255 characters)")
    end

    it "preserves an explicitly provided slug" do
      node = Node.new(title: "My Title", slug: "custom-slug")
      node.valid?
      expect(node.slug).to eq("custom-slug")
    end
  end

  describe "slug auto-generation" do
    it "generates a slug from the title" do
      node = Node.new(title: "Hello World")
      node.valid?
      expect(node.slug).to eq("hello-world")
    end

    it "downcases the title" do
      node = Node.new(title: "UPPERCASE TITLE")
      node.valid?
      expect(node.slug).to eq("uppercase-title")
    end

    it "replaces non-alphanumeric characters with hyphens" do
      node = Node.new(title: "Hello, World! How's it going?")
      node.valid?
      expect(node.slug).to eq("hello-world-how-s-it-going")
    end

    it "collapses consecutive hyphens" do
      node = Node.new(title: "hello---world")
      node.valid?
      expect(node.slug).to eq("hello-world")
    end

    it "strips leading and trailing hyphens" do
      node = Node.new(title: "  Hello World  ")
      node.valid?
      expect(node.slug).to eq("hello-world")
    end

    it "fails validation when title produces an empty slug" do
      node = Node.new(title: "!!!")
      expect(node).not_to be_valid
      expect(node.errors[:slug]).to include("can't be blank")
    end

    it "does not append numeric suffixes for uniqueness" do
      Node.create!(title: "Hello World")
      duplicate = Node.new(title: "Hello World")
      duplicate.valid?
      expect(duplicate.slug).to eq("hello-world")
      expect(duplicate).not_to be_valid
    end

    it "does not overwrite an existing slug" do
      node = Node.new(title: "New Title", slug: "keep-this")
      node.valid?
      expect(node.slug).to eq("keep-this")
    end
  end

  describe "published timestamp behaviour" do
    it "sets published_at when transitioning from false to true" do
      freeze_time do
        node = Node.create!(title: "Test")
        node.update!(published: true)
        expect(node.published_at).to eq(Time.current)
      end
    end

    it "preserves an existing published_at when publishing" do
      custom_time = Time.zone.parse("2025-01-01 12:00:00")
      node = Node.create!(title: "Test")
      node.update!(published: true, published_at: custom_time)
      expect(node.published_at).to eq(custom_time)
    end

    it "preserves published_at when unpublishing" do
      node = Node.create!(title: "Test", published: true)
      original_time = node.published_at
      node.update!(published: false)
      expect(node.published_at).to eq(original_time)
    end

    it "does not modify published_at when published stays true" do
      node = nil
      freeze_time do
        node = Node.create!(title: "Test", published: true)
      end
      original_time = node.published_at

      travel_to 1.day.from_now do
        node.update!(title: "Updated Title")
        expect(node.published_at).to eq(original_time)
      end
    end

    it "does not set published_at when published remains false" do
      node = Node.create!(title: "Test")
      node.update!(title: "Updated Title")
      expect(node.published_at).to be_nil
    end
  end

  describe "database constraints" do
    it "enforces unique index on slug" do
      Node.create!(title: "First", slug: "unique-slug")
      duplicate = Node.new(title: "Second", slug: "unique-slug")
      expect {
        duplicate.save(validate: false)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "enforces NOT NULL on title" do
      node = Node.new(slug: "valid-slug")
      expect {
        node.save(validate: false)
      }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "enforces NOT NULL on slug" do
      node = Node.new(title: "Valid Title")
      node.slug = nil
      expect {
        node.save(validate: false)
      }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "enforces NOT NULL on published" do
      node = Node.new(title: "Valid Title", slug: "valid-slug")
      node.published = nil
      expect {
        node.save(validate: false)
      }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "auto-manages created_at and updated_at timestamps" do
      node = Node.create!(title: "Test")
      expect(node.created_at).to be_present
      expect(node.updated_at).to be_present
    end
  end
end
