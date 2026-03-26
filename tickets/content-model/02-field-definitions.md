# CM-02: Field Definitions

## Summary

Define the FieldDefinition entity — an individual field that belongs to a content type. Field definitions describe the shape of content: their name, type, ordering, and validation rules. This ticket covers the database schema, model validations, and associations only. No UI.

## Dependencies

- **CM-01** — Content type model must exist.

## Requirements

### Schema

| Column          | Type     | Constraints                                   |
|-----------------|----------|-----------------------------------------------|
| id              | integer  | Primary key, auto-increment                   |
| content_type_id | integer  | Not null, FK → content_types, indexed         |
| name            | string   | Not null                                      |
| api_key         | string   | Not null                                      |
| field_type      | string   | Not null                                      |
| required        | boolean  | Not null, default: false                      |
| position        | integer  | Not null, default: 0                          |
| validations     | json     | Nullable                                      |
| created_at      | datetime | Auto-managed                                  |
| updated_at      | datetime | Auto-managed                                  |

A compound unique index must exist on `(content_type_id, api_key)` — each field's API key must be unique within its content type.

### Validations

- **name** — required; maximum 255 characters. This is the human-readable label shown in forms (e.g. "Event Date").
- **api_key** — required; maximum 255 characters; must match the pattern `^[a-z][a-z0-9_]*$` (lowercase, starts with a letter, only letters/digits/underscores). Must be unique within the content type. This is the machine-readable key used in the JSON fields column (e.g. "event_date").
- **field_type** — required; must be one of the allowed types (see below).
- **content_type** — required; must reference an existing content type.
- **position** — required; must be a non-negative integer.

### Allowed Field Types

| Field Type  | Description                                  | Stored As        |
|-------------|----------------------------------------------|------------------|
| `string`    | Short text (single line)                     | String           |
| `text`      | Long text (multi-line, plain)                | String           |
| `rich_text` | Long text (multi-line, formatted)            | String           |
| `integer`   | Whole number                                 | Integer          |
| `decimal`   | Decimal number                               | Number           |
| `boolean`   | True or false                                | Boolean          |
| `date`      | Calendar date                                | ISO 8601 string  |
| `datetime`  | Date and time                                | ISO 8601 string  |
| `reference` | Reference to another node                    | Integer (node ID)|

### Type-Specific Validations

The `validations` JSON column holds optional, type-specific validation configuration. The allowed keys depend on the `field_type`:

| Field Type          | Allowed Validation Keys                          |
|---------------------|--------------------------------------------------|
| `string`            | `min_length` (integer), `max_length` (integer)   |
| `text`, `rich_text` | `min_length` (integer), `max_length` (integer)   |
| `integer`           | `min` (integer), `max` (integer)                 |
| `decimal`           | `min` (number), `max` (number)                   |
| `boolean`           | _(none)_                                         |
| `date`, `datetime`  | _(none)_                                         |
| `reference`         | `allowed_content_types` (array of content type IDs) |

The `validations` column should reject unknown keys for the given field type.

### Associations

- A **content type** has many field definitions, ordered by `position`. Destroying a content type destroys its field definitions (`dependent: :destroy`).
- A **field definition** belongs to a content type.

## Acceptance Criteria

- [ ] Database table `field_definitions` exists with all columns and constraints listed above.
- [ ] A compound unique index exists on `(content_type_id, api_key)`.
- [ ] A foreign key constraint exists on `content_type_id` referencing `content_types`.
- [ ] Creating a field definition without a name fails validation.
- [ ] Creating a field definition without an api_key fails validation.
- [ ] Creating a field definition with an invalid api_key format fails validation (e.g. starts with digit, contains uppercase, contains hyphens).
- [ ] Creating two field definitions with the same api_key on the same content type fails validation.
- [ ] Two field definitions on different content types can share the same api_key.
- [ ] Creating a field definition with an invalid field_type fails validation.
- [ ] Each of the nine allowed field types can be created successfully.
- [ ] The `validations` column accepts valid JSON matching the allowed keys for the field type.
- [ ] The `validations` column rejects unknown keys for the given field type.
- [ ] Destroying a content type cascades to its field definitions.
- [ ] Field definitions are ordered by `position` by default.
- [ ] `created_at` and `updated_at` are automatically managed.

## Security Considerations

- Enforce the compound unique constraint at both the application and database level.
- Validate the `field_type` value against an allowlist — never trust client-provided values without checking.
- Validate the structure of the `validations` JSON to prevent injection of arbitrary configuration.

## Accessibility Considerations

No UI in this ticket — accessibility concerns are addressed in CM-03.

## Implementation Notes

### Rails

- Generate a `FieldDefinition` model with a migration.
- Use `has_many :field_definitions, -> { order(:position) }, dependent: :destroy` on `ContentType`.
- Validate `api_key` format with a regex and uniqueness scoped to `content_type_id`.
- Validate `field_type` inclusion: `validates :field_type, inclusion: { in: FIELD_TYPES }`.
- Use a custom validation method for the `validations` JSON structure, checking allowed keys per field type.
- The `validations` column uses `serialize :validations, coder: JSON` or Rails' native JSON column support.

### Rust (Actix)

- Define a `FieldDefinition` struct with serde for JSON serialization of the `validations` column.
- Use an enum for `field_type` with serde deserialization.
- Implement validation of the `validations` JSON structure as a method on the struct.
- Use a database migration for schema setup with the compound unique index.
