class Node < ApplicationRecord
  has_many :versions, dependent: :destroy

  before_validation :generate_slug_from_title, on: :create

  validates :slug, presence: true,
                   length: { maximum: 255 },
                   format: { with: /\A[a-z0-9]+(-[a-z0-9]+)*\z/ },
                   uniqueness: { case_sensitive: false }

  validate :slug_immutability

  def self.create_with_version(title:, slug: nil, body: nil)
    node = nil
    version = nil

    transaction do
      node = new(slug: slug)
      node.title_for_slug = title if slug.blank?
      node.save!

      main_branch = Branch.find_by!(name: "main")
      version = Version.create!(
        node: node,
        branch: main_branch,
        title: title,
        body: body
      )
    end

    [node, version]
  end

  attr_accessor :title_for_slug

  private

  def generate_slug_from_title
    title_source = title_for_slug
    return if title_source.blank? || slug.present?

    self.slug = title_source
      .downcase
      .gsub(/[^a-z0-9]/, "-")
      .gsub(/-{2,}/, "-")
      .gsub(/\A-|-\z/, "")
  end

  def slug_immutability
    if slug_changed? && persisted?
      errors.add(:slug, "cannot be changed after creation")
    end
  end
end
