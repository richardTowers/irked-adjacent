class Branch < ApplicationRecord
  PROTECTED_NAMES = %w[main published].freeze

  has_many :versions, dependent: :restrict_with_error

  validates :name, presence: true,
                   length: { maximum: 50 },
                   format: { with: /\A[a-z0-9]+(-[a-z0-9]+)*\z/ },
                   uniqueness: { case_sensitive: false }

  validate :prevent_renaming_protected_branch

  before_destroy :prevent_destroying_protected_branch

  def protected?
    name.in?(PROTECTED_NAMES)
  end

  private

  def prevent_renaming_protected_branch
    if name_changed? && persisted? && name_was.in?(PROTECTED_NAMES)
      errors.add(:name, "cannot rename a protected branch")
    end
  end

  def prevent_destroying_protected_branch
    if protected?
      errors.add(:base, "cannot delete a protected branch")
      throw :abort
    end
  end
end
