require 'rails_helper'

RSpec.describe Team, type: :model do
  describe "validations" do
    it "is valid with a name and auto-generated slug" do
      team = Team.new(name: "My Team")
      expect(team).to be_valid
    end

    it "requires a name" do
      team = Team.new(name: nil)
      expect(team).not_to be_valid
      expect(team.errors[:name]).to include("can't be blank")
    end

    it "enforces a maximum name length of 255" do
      team = Team.new(name: "a" * 256)
      expect(team).not_to be_valid
      expect(team.errors[:name]).to include("is too long (maximum is 255 characters)")
    end

    it "accepts a name of exactly 255 characters" do
      team = Team.new(name: "a" * 255)
      expect(team).to be_valid
    end

    it "requires a valid slug format" do
      invalid_slugs = ["Hello", "hello world", "hello--world", "-hello", "hello-", "UPPER", "hello_world"]
      invalid_slugs.each do |bad_slug|
        team = Team.new(name: "Something", slug: bad_slug)
        expect(team).not_to be_valid, "Expected slug '#{bad_slug}' to be invalid"
      end
    end

    it "accepts valid slug formats" do
      valid_slugs = ["hello", "hello-world", "a1-b2-c3", "123"]
      valid_slugs.each do |good_slug|
        team = Team.new(name: "Something", slug: good_slug)
        expect(team).to be_valid, "Expected slug '#{good_slug}' to be valid"
      end
    end

    it "enforces slug uniqueness case-insensitively" do
      Team.create!(name: "First", slug: "my-slug")
      duplicate = Team.new(name: "Second", slug: "my-slug")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:slug]).to include("has already been taken")
    end

    it "enforces a maximum slug length of 255" do
      team = Team.new(name: "Something", slug: "a" * 256)
      expect(team).not_to be_valid
      expect(team.errors[:slug]).to include("is too long (maximum is 255 characters)")
    end

    it "preserves an explicitly provided slug" do
      team = Team.new(name: "My Team", slug: "custom-slug")
      team.valid?
      expect(team.slug).to eq("custom-slug")
    end
  end

  describe "slug auto-generation" do
    it "generates a slug from the name" do
      team = Team.new(name: "Hello World")
      team.valid?
      expect(team.slug).to eq("hello-world")
    end

    it "downcases the name" do
      team = Team.new(name: "UPPERCASE NAME")
      team.valid?
      expect(team.slug).to eq("uppercase-name")
    end

    it "replaces non-alphanumeric characters with hyphens" do
      team = Team.new(name: "Hello, World! How's it going?")
      team.valid?
      expect(team.slug).to eq("hello-world-how-s-it-going")
    end

    it "collapses consecutive hyphens" do
      team = Team.new(name: "hello---world")
      team.valid?
      expect(team.slug).to eq("hello-world")
    end

    it "strips leading and trailing hyphens" do
      team = Team.new(name: "  Hello World  ")
      team.valid?
      expect(team.slug).to eq("hello-world")
    end

    it "fails validation when name produces an empty slug" do
      team = Team.new(name: "!!!")
      expect(team).not_to be_valid
      expect(team.errors[:slug]).to include("can't be blank")
    end

    it "does not append numeric suffixes for uniqueness" do
      Team.create!(name: "Hello World")
      duplicate = Team.new(name: "Hello World")
      duplicate.valid?
      expect(duplicate.slug).to eq("hello-world")
      expect(duplicate).not_to be_valid
    end

    it "does not overwrite an existing slug" do
      team = Team.new(name: "New Name", slug: "keep-this")
      team.valid?
      expect(team.slug).to eq("keep-this")
    end
  end

  describe "associations" do
    it "has many memberships" do
      team = Team.create!(name: "Test Team")
      user = User.create!(email_address: "test@example.com", password: "securepassword1", password_confirmation: "securepassword1")
      team.memberships.create!(user: user)
      expect(team.memberships.count).to eq(1)
    end

    it "has many users through memberships" do
      team = Team.create!(name: "Test Team")
      user = User.create!(email_address: "test@example.com", password: "securepassword1", password_confirmation: "securepassword1")
      team.memberships.create!(user: user)
      expect(team.users).to include(user)
    end

    it "destroys memberships when destroyed" do
      team = Team.create!(name: "Test Team")
      user = User.create!(email_address: "test@example.com", password: "securepassword1", password_confirmation: "securepassword1")
      team.memberships.create!(user: user)

      expect { team.destroy }.to change(Membership, :count).by(-1)
    end
  end

  describe "database constraints" do
    it "enforces unique index on slug" do
      Team.create!(name: "First", slug: "unique-slug")
      duplicate = Team.new(name: "Second", slug: "unique-slug")
      expect {
        duplicate.save(validate: false)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "enforces NOT NULL on name" do
      team = Team.new(slug: "valid-slug")
      expect {
        team.save(validate: false)
      }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "enforces NOT NULL on slug" do
      team = Team.new(name: "Valid Name")
      team.slug = nil
      expect {
        team.save(validate: false)
      }.to raise_error(ActiveRecord::NotNullViolation)
    end
  end
end
