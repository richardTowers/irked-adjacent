class Membership < ApplicationRecord
  ROLES = %w[member editor].freeze

  belongs_to :user
  belongs_to :team

  validates :role, presence: true, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :team_id }
end
