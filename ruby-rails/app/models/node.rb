class Node < ApplicationRecord
  before_validation :generate_slug_from_title
  before_save :set_published_at

  validates :title, presence: true, length: { maximum: 255 }
  validates :slug, presence: true,
                   length: { maximum: 255 },
                   format: { with: /\A[a-z0-9]+(-[a-z0-9]+)*\z/ },
                   uniqueness: { case_sensitive: false }

  private

  def generate_slug_from_title
    return if title.blank? || slug.present?

    self.slug = title
      .downcase
      .gsub(/[^a-z0-9]/, "-")
      .gsub(/-{2,}/, "-")
      .gsub(/\A-|-\z/, "")
  end

  def set_published_at
    if published_changed? && published? && published_at.nil?
      self.published_at = Time.current
    end
  end
end
