module ApplicationHelper
  def field_error_attrs(record, attribute)
    if record.errors[attribute].any?
      { "aria-invalid": "true", "aria-describedby": "field-definition-#{attribute.to_s.dasherize}-error" }
    else
      {}
    end
  end
end
