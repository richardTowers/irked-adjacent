# CORE-01: Node Model and Database Schema

## Summary

Define the Node entity — the primary content building block of the CMS. This ticket covers the database schema, model validations, and slug-generation behaviour. No UI or routes; those come in later tickets.

## Dependencies

None — this is the first ticket.

## Requirements

### Schema

| Column       | Type     | Constraints                        |
|--------------|----------|------------------------------------|
| id           | integer  | Primary key, auto-increment        |
| title        | string   | Not null                           |
| slug         | string   | Not null, unique, indexed          |
| body         | text     | Nullable                           |
| published    | boolean  | Not null, default: false           |
| published_at | datetime | Nullable                           |
| created_at   | datetime | Auto-managed                       |
| updated_at   | datetime | Auto-managed                       |

### Validations

- **title** — required; maximum 255 characters.
- **slug** — required; maximum 255 characters; must match the pattern `^[a-z0-9]+(-[a-z0-9]+)*$` (lowercase letters, digits, and single hyphens between segments — no leading, trailing, or consecutive hyphens); must be unique (case-insensitive).

### Slug Auto-generation

When a node is created or updated with a title but no slug (blank or nil), the slug is derived from the title:

1. Downcase the title.
2. Replace any character that is not a lowercase letter or digit with a hyphen.
3. Collapse consecutive hyphens into one.
4. Strip leading and trailing hyphens.

If the generated slug is empty after processing (e.g. title is all punctuation), validation fails with a message on slug.

Slug uniqueness conflicts are **validation errors** — the system must not silently append numeric suffixes.

### Published Timestamp Behaviour

- When `published` transitions from `false` to `true` and `published_at` is nil, set `published_at` to the current time.
- When `published` transitions from `false` to `true` and `published_at` is already set, preserve the existing value.
- When `published` transitions from `true` to `false`, preserve `published_at` (do not clear it).
- When `published` remains unchanged, do not modify `published_at`.

## Acceptance Criteria

- [ ] Database table `nodes` exists with all columns and constraints listed above.
- [ ] A unique index exists on the `slug` column.
- [ ] Creating a node without a title fails validation with an error on `title`.
- [ ] Creating a node with a title longer than 255 characters fails validation.
- [ ] Creating a node with a valid title and no slug auto-generates the slug from the title.
- [ ] Slug auto-generation downcases, replaces non-alphanumeric characters with hyphens, collapses consecutive hyphens, and strips leading/trailing hyphens.
- [ ] Creating a node with an explicitly provided valid slug uses that slug as-is.
- [ ] Creating a node with a slug that already exists (case-insensitive) fails validation with an error on `slug`.
- [ ] Slug values with uppercase letters, leading/trailing hyphens, consecutive hyphens, or non-alphanumeric characters (other than hyphens) fail validation.
- [ ] A slug longer than 255 characters fails validation.
- [ ] Publishing a node (false -> true) sets `published_at` when it was previously nil.
- [ ] Publishing a node that already has a `published_at` value preserves the existing timestamp.
- [ ] Unpublishing a node (true -> false) does not clear `published_at`.
- [ ] `created_at` and `updated_at` are automatically managed.

## Security Considerations

- Enforce slug uniqueness at both the application and database level (unique index) to prevent race conditions.
- Validate all inputs at the model level regardless of where they originate — do not rely solely on controller-level checks.

## Accessibility Considerations

No UI in this ticket — accessibility concerns are addressed in CORE-02 through CORE-05.

## Implementation Notes

### Rails

- Generate a `Node` model with a migration.
- Use Active Record validations (`presence`, `length`, `uniqueness`, `format`).
- Use a `before_validation` callback for slug auto-generation.
- Use a callback (e.g. `before_save`) for `published_at` logic, checking `published_changed?`.
- Add `add_index :nodes, :slug, unique: true` in the migration.

### Rust (Actix)

- Define a `Node` struct with Diesel or SQLx.
- Implement validation logic in a dedicated method or builder.
- Slug generation can be a standalone function in a `utils` or `models` module.
- Use a database migration tool (Diesel migrations or sqlx-cli) for schema setup.
- `published_at` logic lives in a method called before persisting.
