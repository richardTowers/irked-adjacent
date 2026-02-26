require "rails_helper"

RSpec.describe Version, type: :model do
  let(:main_branch) { Branch.find_by!(name: "main") }
  let(:published_branch) { Branch.find_by!(name: "published") }
  let(:node) { Node.create!(slug: "test-node") }

  def create_committed_version(attrs = {})
    defaults = {
      node: node,
      branch: main_branch,
      title: "Test Title",
      commit_message: "Initial commit",
      committed_at: Time.current
    }
    Version.create!(defaults.merge(attrs))
  end

  describe "validations" do
    it "is valid with required attributes" do
      version = Version.new(node: node, branch: main_branch, title: "Hello")
      expect(version).to be_valid
    end

    it "requires a title" do
      version = Version.new(node: node, branch: main_branch, title: nil)
      expect(version).not_to be_valid
      expect(version.errors[:title]).to include("can't be blank")
    end

    it "enforces a maximum title length of 255" do
      version = Version.new(node: node, branch: main_branch, title: "a" * 256)
      expect(version).not_to be_valid
      expect(version.errors[:title]).to include("is too long (maximum is 255 characters)")
    end

    it "requires a node" do
      version = Version.new(branch: main_branch, title: "Hello")
      expect(version).not_to be_valid
      expect(version.errors[:node]).to be_present
    end

    it "requires a branch" do
      version = Version.new(node: node, title: "Hello")
      expect(version).not_to be_valid
      expect(version.errors[:branch]).to be_present
    end
  end

  describe "commit_message / committed_at consistency" do
    it "fails when commit_message is set without committed_at" do
      version = Version.new(node: node, branch: main_branch, title: "Hello", commit_message: "msg")
      expect(version).not_to be_valid
      expect(version.errors[:commit_message]).to include("cannot be set on an uncommitted version")
    end

    it "fails when committed_at is set without commit_message" do
      version = Version.new(node: node, branch: main_branch, title: "Hello", committed_at: Time.current)
      expect(version).not_to be_valid
      expect(version.errors[:commit_message]).to include("is required when committing")
    end

    it "is valid when both are set" do
      version = Version.new(node: node, branch: main_branch, title: "Hello", commit_message: "msg", committed_at: Time.current)
      expect(version).to be_valid
    end

    it "is valid when both are nil" do
      version = Version.new(node: node, branch: main_branch, title: "Hello")
      expect(version).to be_valid
    end
  end

  describe "immutability" do
    it "prevents modification of committed versions" do
      version = create_committed_version
      version.title = "New Title"
      expect(version).not_to be_valid
      expect(version.errors[:base]).to include("committed versions are immutable")
    end

    it "allows the initial save that sets committed_at" do
      version = Version.new(
        node: node, branch: main_branch, title: "Hello",
        commit_message: "Initial", committed_at: Time.current
      )
      expect(version.save).to be true
    end
  end

  describe "uncommitted uniqueness" do
    it "allows only one uncommitted version per node per branch" do
      Version.create!(node: node, branch: main_branch, title: "First")
      second = Version.new(node: node, branch: main_branch, title: "Second")
      expect(second).not_to be_valid
      expect(second.errors[:base]).to include("an uncommitted version already exists for this node on this branch")
    end

    it "allows uncommitted versions on different branches" do
      other_branch = Branch.create!(name: "feature-1")
      Version.create!(node: node, branch: main_branch, title: "Main draft")
      version = Version.new(node: node, branch: other_branch, title: "Feature draft")
      expect(version).to be_valid
    end

    it "allows a new uncommitted version after the first is committed" do
      first = Version.create!(node: node, branch: main_branch, title: "First")
      first.commit!("Done")
      second = Version.new(node: node, branch: main_branch, title: "Second", parent_version: first)
      expect(second).to be_valid
    end

    it "enforces uniqueness at the database level" do
      Version.create!(node: node, branch: main_branch, title: "First")
      duplicate = Version.new(node: node, branch: main_branch, title: "Second")
      expect {
        duplicate.save(validate: false)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "lineage validations" do
    describe "parent_version_id" do
      it "accepts a parent on the same node and branch" do
        parent = create_committed_version
        child = Version.new(node: node, branch: main_branch, title: "Child", parent_version: parent)
        expect(child).to be_valid
      end

      it "rejects a parent on a different branch" do
        other_branch = Branch.create!(name: "other")
        parent = create_committed_version(branch: other_branch)
        child = Version.new(node: node, branch: main_branch, title: "Child", parent_version: parent)
        expect(child).not_to be_valid
        expect(child.errors[:parent_version_id]).to include("must reference a version of the same node on the same branch")
      end

      it "rejects a parent on a different node" do
        other_node = Node.create!(slug: "other-node")
        parent = create_committed_version(node: other_node)
        child = Version.new(node: node, branch: main_branch, title: "Child", parent_version: parent)
        expect(child).not_to be_valid
        expect(child.errors[:parent_version_id]).to include("must reference a version of the same node on the same branch")
      end
    end

    describe "source_version_id" do
      it "accepts a committed source on the same node" do
        source = create_committed_version
        other_branch = Branch.create!(name: "other")
        version = Version.new(node: node, branch: other_branch, title: "Forked", source_version: source)
        expect(version).to be_valid
      end

      it "rejects an uncommitted source" do
        source = Version.create!(node: node, branch: main_branch, title: "Draft")
        other_branch = Branch.create!(name: "other")
        version = Version.new(node: node, branch: other_branch, title: "Forked", source_version: source)
        expect(version).not_to be_valid
        expect(version.errors[:source_version_id]).to include("must reference a committed version")
      end

      it "rejects a source on a different node" do
        other_node = Node.create!(slug: "other-node")
        source = create_committed_version(node: other_node)
        other_branch = Branch.create!(name: "other")
        version = Version.new(node: node, branch: other_branch, title: "Forked", source_version: source)
        expect(version).not_to be_valid
        expect(version.errors[:source_version_id]).to include("must reference a version of the same node")
      end
    end
  end

  describe "published branch restrictions" do
    it "prevents creating uncommitted versions on the published branch" do
      version = Version.new(node: node, branch: published_branch, title: "Draft")
      expect(version).not_to be_valid
      expect(version.errors[:base]).to include("cannot create uncommitted versions on the published branch")
    end

    it "prevents direct commits to the published branch (without source_version)" do
      version = Version.new(
        node: node, branch: published_branch, title: "Direct",
        commit_message: "Direct commit", committed_at: Time.current
      )
      expect(version).not_to be_valid
      expect(version.errors[:base]).to include("versions on the published branch can only be created by publishing")
    end
  end

  describe ".current_for" do
    it "returns the uncommitted version if one exists" do
      uncommitted = Version.create!(node: node, branch: main_branch, title: "Draft")
      expect(Version.current_for(node, main_branch)).to eq(uncommitted)
    end

    it "returns the latest committed version when no uncommitted exists" do
      freeze_time do
        create_committed_version(title: "Older", committed_at: 1.hour.ago)
        newer = create_committed_version(title: "Newer", committed_at: Time.current, parent_version: nil)
        expect(Version.current_for(node, main_branch)).to eq(newer)
      end
    end

    it "returns nil when no versions exist for the node on the branch" do
      expect(Version.current_for(node, main_branch)).to be_nil
    end

    it "prefers uncommitted over committed" do
      create_committed_version
      uncommitted = Version.create!(node: node, branch: main_branch, title: "Draft")
      expect(Version.current_for(node, main_branch)).to eq(uncommitted)
    end
  end

  describe "#commit!" do
    it "commits an uncommitted version" do
      version = Version.create!(node: node, branch: main_branch, title: "Draft")

      freeze_time do
        version.commit!("First commit")
        expect(version.committed_at).to eq(Time.current)
        expect(version.commit_message).to eq("First commit")
      end
    end

    it "raises an error when committing an already committed version" do
      version = create_committed_version
      expect {
        version.commit!("Again")
      }.to raise_error(ActiveRecord::RecordInvalid)
      expect(version.errors[:base]).to include("version is already committed")
    end

    it "raises an error when commit message is blank" do
      version = Version.create!(node: node, branch: main_branch, title: "Draft")
      expect {
        version.commit!("")
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "allows empty commits (no content change from parent)" do
      parent = create_committed_version(title: "Same")
      child = Version.create!(node: node, branch: main_branch, title: "Same", parent_version: parent)
      expect { child.commit!("Empty commit") }.not_to raise_error
    end
  end

  describe ".publish!" do
    let!(:committed_version) { create_committed_version }

    it "creates a committed version on the published branch" do
      published = Version.publish!(committed_version)

      expect(published).to be_persisted
      expect(published.branch).to eq(published_branch)
      expect(published.committed_at).to be_present
      expect(published.title).to eq(committed_version.title)
      expect(published.body).to eq(committed_version.body)
      expect(published.source_version).to eq(committed_version)
      expect(published.commit_message).to eq("Publish from main")
    end

    it "sets parent_version to the latest published version of the same node" do
      first_published = Version.publish!(committed_version)

      new_committed = create_committed_version(title: "Updated", committed_at: Time.current)
      second_published = Version.publish!(new_committed)

      expect(second_published.parent_version).to eq(first_published)
    end

    it "fails when source version is uncommitted" do
      draft = Version.create!(node: node, branch: main_branch, title: "Draft")
      expect {
        Version.publish!(draft)
      }.to raise_error(ActiveRecord::RecordInvalid, /cannot publish an uncommitted version/)
    end

    it "fails when source version is on the published branch" do
      published_version = Version.publish!(committed_version)
      expect {
        Version.publish!(published_version)
      }.to raise_error(ActiveRecord::RecordInvalid, /cannot publish from the published branch/)
    end
  end

  describe "scopes" do
    it ".committed returns only committed versions" do
      create_committed_version
      Version.create!(node: node, branch: main_branch, title: "Draft")
      expect(Version.committed.count).to eq(1)
    end

    it ".uncommitted returns only uncommitted versions" do
      create_committed_version
      Version.create!(node: node, branch: main_branch, title: "Draft")
      expect(Version.uncommitted.count).to eq(1)
    end
  end
end
