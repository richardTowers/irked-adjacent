require "rails_helper"

RSpec.describe Branch, type: :model do
  describe "validations" do
    it "is valid with a valid name" do
      branch = Branch.new(name: "feature-1")
      expect(branch).to be_valid
    end

    it "requires a name" do
      branch = Branch.new(name: nil)
      expect(branch).not_to be_valid
      expect(branch.errors[:name]).to include("can't be blank")
    end

    it "enforces a maximum name length of 50" do
      branch = Branch.new(name: "a" * 51)
      expect(branch).not_to be_valid
      expect(branch.errors[:name]).to include("is too long (maximum is 50 characters)")
    end

    it "accepts a name of exactly 50 characters" do
      branch = Branch.new(name: "a" * 50)
      expect(branch).to be_valid
    end

    it "requires a valid name format" do
      invalid_names = ["Hello", "hello world", "hello--world", "-hello", "hello-", "UPPER", "hello_world"]
      invalid_names.each do |bad_name|
        branch = Branch.new(name: bad_name)
        expect(branch).not_to be_valid, "Expected name '#{bad_name}' to be invalid"
        expect(branch.errors[:name]).to be_present
      end
    end

    it "accepts valid name formats" do
      valid_names = ["hello", "hello-world", "a1-b2-c3", "123", "feature-1"]
      valid_names.each do |good_name|
        branch = Branch.new(name: good_name)
        expect(branch).to be_valid, "Expected name '#{good_name}' to be valid"
      end
    end

    it "enforces name uniqueness case-insensitively" do
      Branch.create!(name: "my-branch")
      duplicate = Branch.new(name: "my-branch")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include("has already been taken")
    end
  end

  describe "#protected?" do
    it "returns true for main" do
      expect(Branch.find_by(name: "main")).to be_protected
    end

    it "returns true for published" do
      expect(Branch.find_by(name: "published")).to be_protected
    end

    it "returns false for other branches" do
      branch = Branch.create!(name: "feature-1")
      expect(branch).not_to be_protected
    end
  end

  describe "protected branch enforcement" do
    it "prevents deletion of the main branch" do
      main = Branch.find_by!(name: "main")
      expect(main.destroy).to be false
      expect(main.errors[:base]).to include("cannot delete a protected branch")
    end

    it "prevents deletion of the published branch" do
      published = Branch.find_by!(name: "published")
      expect(published.destroy).to be false
      expect(published.errors[:base]).to include("cannot delete a protected branch")
    end

    it "allows deletion of non-protected branches" do
      branch = Branch.create!(name: "temp-branch")
      expect(branch.destroy).to be_truthy
      expect(Branch.find_by(name: "temp-branch")).to be_nil
    end

    it "prevents renaming the main branch" do
      main = Branch.find_by!(name: "main")
      main.name = "renamed"
      expect(main).not_to be_valid
      expect(main.errors[:name]).to include("cannot rename a protected branch")
    end

    it "prevents renaming the published branch" do
      published = Branch.find_by!(name: "published")
      published.name = "renamed"
      expect(published).not_to be_valid
      expect(published.errors[:name]).to include("cannot rename a protected branch")
    end
  end
end
