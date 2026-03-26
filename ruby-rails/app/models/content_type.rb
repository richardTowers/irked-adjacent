class ContentType < ApplicationRecord
  include Sluggable

  belongs_to :team
  has_many :field_definitions, -> { order(:position) }, dependent: :destroy
  has_many :nodes, dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 255 }

  private

  def slug_source_value
    name
  end
end
