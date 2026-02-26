class Version < ApplicationRecord
  belongs_to :node
  belongs_to :branch
  belongs_to :parent_version, class_name: "Version", optional: true
  belongs_to :source_version, class_name: "Version", optional: true

  validates :title, presence: true, length: { maximum: 255 }

  validate :commit_message_and_committed_at_consistency
  validate :enforce_immutability
  validate :enforce_uncommitted_uniqueness
  validate :validate_parent_version_lineage
  validate :validate_source_version_lineage
  validate :enforce_published_branch_restrictions

  scope :committed, -> { where.not(committed_at: nil) }
  scope :uncommitted, -> { where(committed_at: nil) }

  def self.current_for(node, branch)
    uncommitted = where(node: node, branch: branch, committed_at: nil).first
    return uncommitted if uncommitted

    where(node: node, branch: branch)
      .where.not(committed_at: nil)
      .order(committed_at: :desc)
      .first
  end

  def commit!(message)
    raise ActiveRecord::RecordInvalid.new(self) if committed_at.present? && tap { errors.add(:base, "version is already committed") }

    self.commit_message = message
    self.committed_at = Time.current
    save!
  end

  def self.publish!(source_version)
    if source_version.committed_at.nil?
      source_version.errors.add(:base, "cannot publish an uncommitted version")
      raise ActiveRecord::RecordInvalid.new(source_version)
    end

    published_branch = Branch.find_by!(name: "published")

    if source_version.branch_id == published_branch.id
      source_version.errors.add(:base, "cannot publish from the published branch")
      raise ActiveRecord::RecordInvalid.new(source_version)
    end

    parent = where(node_id: source_version.node_id, branch: published_branch)
               .where.not(committed_at: nil)
               .order(committed_at: :desc)
               .first

    create!(
      node_id: source_version.node_id,
      branch: published_branch,
      title: source_version.title,
      body: source_version.body,
      parent_version: parent,
      source_version: source_version,
      commit_message: "Publish from #{source_version.branch.name}",
      committed_at: Time.current
    )
  end

  private

  def commit_message_and_committed_at_consistency
    if committed_at.present? && commit_message.blank?
      errors.add(:commit_message, "is required when committing")
    elsif commit_message.present? && committed_at.nil?
      errors.add(:commit_message, "cannot be set on an uncommitted version")
    end
  end

  def enforce_immutability
    return unless persisted? && committed_at_in_database.present?

    if changed?
      errors.add(:base, "committed versions are immutable")
    end
  end

  def enforce_uncommitted_uniqueness
    return if committed_at.present?
    return unless node_id.present? && branch_id.present?

    existing = self.class.where(node_id: node_id, branch_id: branch_id, committed_at: nil)
    existing = existing.where.not(id: id) if persisted?

    if existing.exists?
      errors.add(:base, "an uncommitted version already exists for this node on this branch")
    end
  end

  def validate_parent_version_lineage
    return if parent_version_id.nil?

    parent = parent_version
    return unless parent

    if parent.node_id != node_id || parent.branch_id != branch_id
      errors.add(:parent_version_id, "must reference a version of the same node on the same branch")
    end
  end

  def validate_source_version_lineage
    return if source_version_id.nil?

    source = source_version
    return unless source

    if source.node_id != node_id
      errors.add(:source_version_id, "must reference a version of the same node")
    end

    if source.committed_at.nil?
      errors.add(:source_version_id, "must reference a committed version")
    end
  end

  def enforce_published_branch_restrictions
    return unless branch_id.present?

    published_branch = Branch.find_by(name: "published")
    return unless published_branch && branch_id == published_branch.id

    if committed_at.nil?
      errors.add(:base, "cannot create uncommitted versions on the published branch")
    elsif !source_version_id.present?
      errors.add(:base, "versions on the published branch can only be created by publishing")
    end
  end
end
