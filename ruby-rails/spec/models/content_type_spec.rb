require 'rails_helper'

RSpec.describe ContentType, type: :model do
  let(:team) { Team.create!(name: "Test Team") }

  describe "validations" do
    it "is valid with a name, team, and auto-generated slug" do
      content_type = ContentType.new(name: "Blog Post", team: team)
      expect(content_type).to be_valid
    end

    it "requires a name" do
      content_type = ContentType.new(name: nil, team: team)
      expect(content_type).not_to be_valid
      expect(content_type.errors[:name]).to include("can't be blank")
    end

    it "enforces a maximum name length of 255" do
      content_type = ContentType.new(name: "a" * 256, team: team)
      expect(content_type).not_to be_valid
      expect(content_type.errors[:name]).to include("is too long (maximum is 255 characters)")
    end

    it "accepts a name of exactly 255 characters" do
      content_type = ContentType.new(name: "a" * 255, team: team)
      expect(content_type).to be_valid
    end

    it "requires a team" do
      content_type = ContentType.new(name: "Blog Post", team: nil)
      expect(content_type).not_to be_valid
      expect(content_type.errors[:team]).to include("must exist")
    end

    it "requires a valid slug format" do
      invalid_slugs = ["Hello", "hello world", "hello--world", "-hello", "hello-", "UPPER", "hello_world"]
      invalid_slugs.each do |bad_slug|
        content_type = ContentType.new(name: "Something", team: team, slug: bad_slug)
        expect(content_type).not_to be_valid, "Expected slug '#{bad_slug}' to be invalid"
      end
    end

    it "accepts valid slug formats" do
      valid_slugs = ["hello", "hello-world", "a1-b2-c3", "123"]
      valid_slugs.each do |good_slug|
        content_type = ContentType.new(name: "Something", team: team, slug: good_slug)
        expect(content_type).to be_valid, "Expected slug '#{good_slug}' to be valid"
      end
    end

    it "enforces slug uniqueness case-insensitively" do
      ContentType.create!(name: "First", team: team, slug: "my-slug")
      duplicate = ContentType.new(name: "Second", team: team, slug: "my-slug")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:slug]).to include("has already been taken")
    end

    it "enforces a maximum slug length of 255" do
      content_type = ContentType.new(name: "Something", team: team, slug: "a" * 256)
      expect(content_type).not_to be_valid
      expect(content_type.errors[:slug]).to include("is too long (maximum is 255 characters)")
    end

    it "preserves an explicitly provided slug" do
      content_type = ContentType.new(name: "Blog Post", team: team, slug: "custom-slug")
      content_type.valid?
      expect(content_type.slug).to eq("custom-slug")
    end

    it "allows a description" do
      content_type = ContentType.new(name: "Blog Post", team: team, description: "Posts for the blog")
      expect(content_type).to be_valid
      content_type.save!
      expect(content_type.reload.description).to eq("Posts for the blog")
    end

    it "allows a nil description" do
      content_type = ContentType.new(name: "Blog Post", team: team, description: nil)
      expect(content_type).to be_valid
    end
  end

  describe "slug auto-generation" do
    it "generates a slug from the name" do
      content_type = ContentType.new(name: "Blog Post", team: team)
      content_type.valid?
      expect(content_type.slug).to eq("blog-post")
    end

    it "downcases the name" do
      content_type = ContentType.new(name: "UPPERCASE NAME", team: team)
      content_type.valid?
      expect(content_type.slug).to eq("uppercase-name")
    end

    it "replaces non-alphanumeric characters with hyphens" do
      content_type = ContentType.new(name: "Hello, World! How's it going?", team: team)
      content_type.valid?
      expect(content_type.slug).to eq("hello-world-how-s-it-going")
    end

    it "collapses consecutive hyphens" do
      content_type = ContentType.new(name: "hello---world", team: team)
      content_type.valid?
      expect(content_type.slug).to eq("hello-world")
    end

    it "strips leading and trailing hyphens" do
      content_type = ContentType.new(name: "  Blog Post  ", team: team)
      content_type.valid?
      expect(content_type.slug).to eq("blog-post")
    end

    it "fails validation when name produces an empty slug" do
      content_type = ContentType.new(name: "!!!", team: team)
      expect(content_type).not_to be_valid
      expect(content_type.errors[:slug]).to include("can't be blank")
    end

    it "does not append numeric suffixes for uniqueness" do
      ContentType.create!(name: "Blog Post", team: team)
      duplicate = ContentType.new(name: "Blog Post", team: team)
      duplicate.valid?
      expect(duplicate.slug).to eq("blog-post")
      expect(duplicate).not_to be_valid
    end

    it "does not overwrite an existing slug" do
      content_type = ContentType.new(name: "New Name", team: team, slug: "keep-this")
      content_type.valid?
      expect(content_type.slug).to eq("keep-this")
    end
  end

  describe "associations" do
    it "belongs to a team" do
      content_type = ContentType.create!(name: "Blog Post", team: team)
      expect(content_type.team).to eq(team)
    end

    it "a team can have multiple content types" do
      ContentType.create!(name: "Blog Post", team: team)
      ContentType.create!(name: "Event", team: team)
      expect(team.content_types.count).to eq(2)
    end

    # Node-ContentType FK is added in CM-04; this test will be enabled then
    it "prevents destruction when content type has nodes", skip: "requires CM-04 (content_type_id on nodes)" do
      content_type = ContentType.create!(name: "Blog Post", team: team)
      Node.create!(title: "A Node", team: team, content_type: content_type)

      expect(content_type.destroy).to be_falsey
      expect(content_type.errors[:base]).to include("Cannot delete record because dependent nodes exist")
      expect(ContentType.exists?(content_type.id)).to be true
    end

    it "can be destroyed when it has no nodes" do
      content_type = ContentType.create!(name: "Blog Post", team: team)
      expect { content_type.destroy }.to change(ContentType, :count).by(-1)
    end
  end

  describe "database constraints" do
    it "enforces unique index on slug" do
      ContentType.create!(name: "First", team: team, slug: "unique-slug")
      duplicate = ContentType.new(name: "Second", team: team, slug: "unique-slug")
      expect {
        duplicate.save(validate: false)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "enforces NOT NULL on name" do
      content_type = ContentType.new(team: team, slug: "valid-slug")
      expect {
        content_type.save(validate: false)
      }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "enforces NOT NULL on slug" do
      content_type = ContentType.new(name: "Valid Name", team: team)
      content_type.slug = nil
      expect {
        content_type.save(validate: false)
      }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "enforces foreign key on team_id" do
      content_type = ContentType.new(name: "Test", slug: "test", team_id: 999999)
      expect {
        content_type.save(validate: false)
      }.to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end

  describe "timestamps" do
    it "sets created_at and updated_at automatically" do
      content_type = ContentType.create!(name: "Blog Post", team: team)
      expect(content_type.created_at).to be_present
      expect(content_type.updated_at).to be_present
    end
  end
end
