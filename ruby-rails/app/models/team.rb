class Team < ApplicationRecord
  include Sluggable

  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships

  validates :name, presence: true, length: { maximum: 255 }

  private

  def slug_source_value
    name
  end
end
