class Node < ApplicationRecord
  include Sluggable

  before_save :set_published_at

  validates :title, presence: true, length: { maximum: 255 }

  private

  def slug_source_value
    title
  end

  def set_published_at
    if published_changed? && published? && published_at.nil?
      self.published_at = Time.current
    end
  end
end
