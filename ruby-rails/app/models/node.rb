class Node < ApplicationRecord
  include Sluggable

  attribute :fields, :json, default: -> { {} }

  belongs_to :team, optional: true
  belongs_to :content_type

  before_save :set_published_at

  validates :title, presence: true, length: { maximum: 255 }
  validates :team_id, presence: true, if: -> { new_record? || team_id_was.present? }
  validates :content_type_id, presence: true
  validate :content_type_belongs_to_same_team
  validates_with FieldsValidator

  private

  def slug_source_value
    title
  end

  def set_published_at
    if published_changed? && published? && published_at.nil?
      self.published_at = Time.current
    end
  end

  def content_type_belongs_to_same_team
    return unless content_type && team_id

    if content_type.team_id != team_id
      errors.add(:content_type, "must belong to the same team as the node")
    end
  end
end
