class FieldsValidator < ActiveModel::Validator
  def validate(record)
    return unless record.content_type

    field_definitions = record.content_type.field_definitions
    fields = record.fields || {}

    validate_no_unknown_keys(record, fields, field_definitions)
    field_definitions.each do |field_def|
      validate_field(record, fields, field_def)
    end
  end

  private

  def validate_no_unknown_keys(record, fields, field_definitions)
    allowed_keys = field_definitions.map(&:api_key).to_set
    unknown_keys = fields.keys.reject { |k| allowed_keys.include?(k) }
    unknown_keys.each do |key|
      record.errors.add("fields.#{key}", "is not a valid field")
    end
  end

  def validate_field(record, fields, field_def)
    key = field_def.api_key
    value = fields[key]
    error_key = "fields.#{key}"

    if field_def.required?
      if !fields.key?(key) || value.nil? || (value.is_a?(String) && value.blank?)
        record.errors.add(error_key, "can't be blank")
        return
      end
    end

    return unless fields.key?(key) && !value.nil?

    validate_type(record, error_key, value, field_def)
  end

  def validate_type(record, error_key, value, field_def)
    case field_def.field_type
    when "string", "text", "rich_text"
      validate_string_type(record, error_key, value, field_def)
    when "integer"
      validate_integer_type(record, error_key, value, field_def)
    when "decimal"
      validate_decimal_type(record, error_key, value, field_def)
    when "boolean"
      validate_boolean_type(record, error_key, value)
    when "date"
      validate_date_type(record, error_key, value)
    when "datetime"
      validate_datetime_type(record, error_key, value)
    when "reference"
      validate_reference_type(record, error_key, value, field_def)
    end
  end

  def validate_string_type(record, error_key, value, field_def)
    unless value.is_a?(String)
      record.errors.add(error_key, "must be a string")
      return
    end

    validations = field_def.validations || {}
    if validations["min_length"] && value.length < validations["min_length"]
      record.errors.add(error_key, "is too short (minimum is #{validations["min_length"]} characters)")
    end
    if validations["max_length"] && value.length > validations["max_length"]
      record.errors.add(error_key, "is too long (maximum is #{validations["max_length"]} characters)")
    end
  end

  def validate_integer_type(record, error_key, value, field_def)
    unless value.is_a?(Integer)
      record.errors.add(error_key, "must be an integer")
      return
    end

    validate_numeric_range(record, error_key, value, field_def)
  end

  def validate_decimal_type(record, error_key, value, field_def)
    unless value.is_a?(Numeric)
      record.errors.add(error_key, "must be a number")
      return
    end

    validate_numeric_range(record, error_key, value, field_def)
  end

  def validate_numeric_range(record, error_key, value, field_def)
    validations = field_def.validations || {}
    if validations["min"] && value < validations["min"]
      record.errors.add(error_key, "must be greater than or equal to #{validations["min"]}")
    end
    if validations["max"] && value > validations["max"]
      record.errors.add(error_key, "must be less than or equal to #{validations["max"]}")
    end
  end

  def validate_boolean_type(record, error_key, value)
    unless value.is_a?(TrueClass) || value.is_a?(FalseClass)
      record.errors.add(error_key, "must be true or false")
    end
  end

  def validate_date_type(record, error_key, value)
    unless value.is_a?(String)
      record.errors.add(error_key, "must be a string in ISO 8601 date format (YYYY-MM-DD)")
      return
    end

    unless value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      record.errors.add(error_key, "must be a valid date in ISO 8601 format (YYYY-MM-DD)")
      return
    end

    Date.parse(value)
  rescue Date::Error
    record.errors.add(error_key, "must be a valid date in ISO 8601 format (YYYY-MM-DD)")
  end

  def validate_datetime_type(record, error_key, value)
    unless value.is_a?(String)
      record.errors.add(error_key, "must be a string in ISO 8601 datetime format")
      return
    end

    unless value.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/)
      record.errors.add(error_key, "must be a valid datetime in ISO 8601 format")
      return
    end

    Time.iso8601(value)
  rescue ArgumentError
    record.errors.add(error_key, "must be a valid datetime in ISO 8601 format")
  end

  def validate_reference_type(record, error_key, value, field_def)
    unless value.is_a?(Integer)
      record.errors.add(error_key, "must be an integer")
      return
    end

    referenced_node = Node.find_by(id: value)
    unless referenced_node
      record.errors.add(error_key, "references a node that does not exist")
      return
    end

    validations = field_def.validations || {}
    allowed_types = validations["allowed_content_types"]
    if allowed_types.present? && !allowed_types.include?(referenced_node.content_type_id)
      record.errors.add(error_key, "references a node with a disallowed content type")
    end
  end
end
