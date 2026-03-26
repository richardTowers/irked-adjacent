class FieldDefinition < ApplicationRecord
  FIELD_TYPES = %w[string text rich_text integer decimal boolean date datetime reference].freeze

  ALLOWED_VALIDATION_KEYS = {
    "string" => %w[min_length max_length],
    "text" => %w[min_length max_length],
    "rich_text" => %w[min_length max_length],
    "integer" => %w[min max],
    "decimal" => %w[min max],
    "boolean" => [],
    "date" => [],
    "datetime" => [],
    "reference" => %w[allowed_content_types]
  }.freeze

  belongs_to :content_type

  validates :name, presence: true, length: { maximum: 255 }
  validates :api_key, presence: true, length: { maximum: 255 },
    format: { with: /\A[a-z][a-z0-9_]*\z/, message: "must start with a lowercase letter and contain only lowercase letters, digits, and underscores" },
    uniqueness: { scope: :content_type_id }
  validates :field_type, presence: true, inclusion: { in: FIELD_TYPES }
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  validate :validate_validations_structure

  private

  def validate_validations_structure
    return if validations.blank?

    unless validations.is_a?(Hash)
      errors.add(:validations, "must be a JSON object")
      return
    end

    allowed_keys = ALLOWED_VALIDATION_KEYS[field_type] || []
    unknown_keys = validations.keys - allowed_keys

    if unknown_keys.any?
      errors.add(:validations, "contains unknown keys for #{field_type} field type: #{unknown_keys.join(', ')}")
    end
  end
end
