# CM-04: Node–Content Type Association, Fields Column, and Body Migration

## Summary

Link nodes to content types by adding a `content_type_id` foreign key and a `fields` JSON column to the nodes table. Implement field validation that checks node field values against the content type's field definitions. Migrate the existing `body` column data into the new fields system by creating a default "Page" content type per team, then remove the `body` column.

## Dependencies

- **CM-01** — Content type model must exist.
- **CM-02** — Field definition model must exist.

## Requirements

### Schema Changes to `nodes`

| Column          | Type    | Constraints                    |
|-----------------|---------|--------------------------------|
| content_type_id | integer | Not null, FK → content_types   |
| fields          | json    | Not null, default: '{}'        |

### Body Migration Strategy

The existing `body` text column must be migrated into the new fields system:

1. Add `content_type_id` (nullable initially) and `fields` columns to `nodes`.
2. For each team that has nodes: create a "Page" content type with a single field definition (`name: "Body"`, `api_key: "body"`, `field_type: "text"`, `required: false`, `position: 0`).
3. For each existing node: set `content_type_id` to the team's "Page" content type and copy the `body` value into the `fields` JSON as `{"body": "<body value>"}`. If `body` is null, set fields to `{}`.
4. For nodes without a team: assign them to a team first (or handle as an edge case — see implementation notes).
5. Make `content_type_id` not null (change the column constraint after data migration).
6. Remove the `body` column.

After this migration, every node has a content type and all content lives in the `fields` JSON column.

### Node–Content Type Association

- A **node** belongs to a content type (required).
- A **content type** has many nodes.
- The content type must belong to the same team as the node. Validate that `node.team_id == node.content_type.team_id`.

### Field Validation

When a node has a content type, the `fields` JSON must be validated against the content type's field definitions:

#### Structural Validation
- Only keys matching field definition `api_key` values are allowed — reject unknown keys.
- Required fields (where `required: true`) must be present and non-blank.

#### Type Validation

| Field Type  | Valid Values                                              |
|-------------|-----------------------------------------------------------|
| `string`    | Must be a string                                          |
| `text`      | Must be a string                                          |
| `rich_text` | Must be a string                                          |
| `integer`   | Must be an integer                                        |
| `decimal`   | Must be a number (integer or float)                       |
| `boolean`   | Must be `true` or `false`                                 |
| `date`      | Must be a string matching ISO 8601 date format (YYYY-MM-DD) |
| `datetime`  | Must be a string matching ISO 8601 datetime format        |
| `reference` | Must be an integer; the referenced node must exist        |

#### Type-Specific Validations

When a field definition has a `validations` JSON, apply the constraints:

- `min_length` / `max_length` — check string length (for `string`, `text`, `rich_text`).
- `min` / `max` — check numeric value (for `integer`, `decimal`).
- `allowed_content_types` — for `reference` fields, the referenced node's `content_type_id` must be in the allowed list (if specified).

#### Error Reporting

Validation errors on individual fields must be reported with the field's `api_key` as the error key, so that errors can be rendered next to the correct form input in CM-05. For example:

```
fields.event_date: "can't be blank"
fields.max_attendees: "must be greater than 0"
```

### Validator Extraction

The field validation logic must be extracted into a dedicated validator class (e.g. `FieldsValidator`) rather than inlined in the Node model. This keeps the Node model focused and makes the validation logic testable in isolation.

## Acceptance Criteria

- [ ] The `nodes` table has a `content_type_id` column with a foreign key to `content_types`.
- [ ] The `nodes` table has a `fields` JSON column with a default of `{}`.
- [ ] The `body` column has been removed from the `nodes` table.
- [ ] Existing nodes have been migrated: each has a content type and its body content is in `fields`.
- [ ] A "Page" content type exists for each team that had nodes, with a "body" text field.
- [ ] Every node has a non-null `content_type_id`.
- [ ] Creating a node without a content type fails validation.
- [ ] A node's content type must belong to the same team as the node.
- [ ] Fields matching the content type's field definitions are accepted.
- [ ] Unknown field keys (not matching any field definition api_key) are rejected.
- [ ] Required fields that are missing or blank fail validation.
- [ ] String fields reject non-string values.
- [ ] Integer fields reject non-integer values.
- [ ] Decimal fields reject non-numeric values.
- [ ] Boolean fields reject non-boolean values.
- [ ] Date fields reject invalid date strings.
- [ ] Datetime fields reject invalid datetime strings.
- [ ] Reference fields reject non-existent node IDs.
- [ ] Reference fields with `allowed_content_types` validation reject nodes of the wrong content type.
- [ ] String field `min_length` and `max_length` validations are enforced.
- [ ] Numeric field `min` and `max` validations are enforced.
- [ ] Validation errors are keyed by field api_key (e.g. `fields.event_date`).
- [ ] Existing acceptance tests pass after migration (with updated expectations for the new schema).

## Security Considerations

- Validate that the content type belongs to the same team as the node — do not allow cross-team content type assignment.
- Validate the `fields` JSON structure server-side — do not trust client-provided JSON without checking it against the field definitions.
- Reference fields must validate that the referenced node exists and is accessible — do not allow references to nodes in other teams unless explicitly permitted.
- The data migration must handle edge cases (null bodies, nodes without teams) without data loss.

## Accessibility Considerations

No UI in this ticket — accessibility concerns for field-level error rendering are addressed in CM-05.

## Implementation Notes

### Rails

- Create a migration that: adds `content_type_id` and `fields` to nodes, performs data migration, makes `content_type_id` not null, removes `body`.
- Consider splitting into two migrations if the data migration is complex: one structural, one for data, one to finalize constraints and drop `body`.
- Add `belongs_to :content_type` to `Node` and `has_many :nodes` to `ContentType`.
- Create `app/validators/fields_validator.rb` as a custom validator class.
- Use `validate :validate_fields` in the Node model, delegating to the `FieldsValidator`.
- The `fields` column with SQLite uses `t.json` — Rails handles serialization as TEXT.
- Handle edge case: nodes without a `team_id` cannot be assigned a "Page" content type. Options: skip them, create a special "unassigned" team, or fail the migration. Document the chosen approach.
- Update existing node factories/fixtures in tests to include `content_type`.

### Rust (Actix)

- Add `content_type_id` and `fields` (as `serde_json::Value`) to the `Node` struct.
- Implement field validation as a dedicated module.
- Use SQLx or Diesel migrations for schema changes.
- The data migration may need to be a Rust script or a SQL migration with embedded logic.
