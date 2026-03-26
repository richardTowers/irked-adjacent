module Sluggable
  extend ActiveSupport::Concern

  included do
    before_validation :generate_slug_from_name_field

    validates :slug, presence: true,
                     length: { maximum: 255 },
                     format: { with: /\A[a-z0-9]+(-[a-z0-9]+)*\z/ },
                     uniqueness: { case_sensitive: false }
  end

  private

  def generate_slug_from_name_field
    source = slug_source_value
    return if source.blank? || slug.present?

    self.slug = source
      .downcase
      .gsub(/[^a-z0-9]/, "-")
      .gsub(/-{2,}/, "-")
      .gsub(/\A-|-\z/, "")
  end

  # Override in including class if the source field is not :title
  def slug_source_value
    respond_to?(:title) ? title : name
  end
end
