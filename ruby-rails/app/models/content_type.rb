class ContentType < ApplicationRecord
  include Sluggable

  belongs_to :team
  has_many :field_definitions, -> { order(:position) }, dependent: :destroy
  # has_many :nodes added in CM-04 when content_type_id column is added to nodes

  validates :name, presence: true, length: { maximum: 255 }

  private

  def slug_source_value
    name
  end
end
