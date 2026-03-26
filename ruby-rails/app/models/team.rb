class Team < ApplicationRecord
  include Sluggable

  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :content_types, dependent: :restrict_with_error
  has_many :nodes, dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 255 }

  private

  def slug_source_value
    name
  end
end
