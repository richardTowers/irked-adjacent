# CM-01: Content Type Model and Schema

## Summary

Define the ContentType entity — the schema definition that describes what kind of node can be created. A content type has a name (e.g. "Blog Post", "Event") and belongs to a team. This ticket covers the database schema, model validations, and associations only. No UI or field definitions; those come in later tickets.

## Dependencies

- **AUTH-01** — Team model must exist (content types belong to teams).

## Requirements

### Schema

| Column      | Type     | Constraints                 |
|-------------|----------|-----------------------------|
| id          | integer  | Primary key, auto-increment |
| name        | string   | Not null                    |
| slug        | string   | Not null, unique, indexed   |
| description | text     | Nullable                    |
| team_id     | integer  | Not null, FK → teams        |
| created_at  | datetime | Auto-managed                |
| updated_at  | datetime | Auto-managed                |

### Validations

- **name** — required; maximum 255 characters.
- **slug** — required; maximum 255 characters; must match the pattern `^[a-z0-9]+(-[a-z0-9]+)*$` (same slug rules as nodes and teams); must be unique (case-insensitive).
- **team** — required; must reference an existing team.

### Slug Auto-generation

When a content type is created or updated with a name but no slug (blank or nil), the slug is derived from the name using the same rules as node and team slug generation:

1. Downcase the name.
2. Replace any character that is not a lowercase letter or digit with a hyphen.
3. Collapse consecutive hyphens into one.
4. Strip leading and trailing hyphens.

Slug uniqueness conflicts are validation errors — no silent suffixing.

### Associations

- A **team** has many content types.
- A **content type** belongs to a team.
- A **content type** has many nodes (added in CM-04, but the association direction is established here).
- Destroying a content type is blocked if any nodes reference it (`dependent: :restrict_with_error`).

## Acceptance Criteria

- [ ] Database table `content_types` exists with all columns and constraints listed above.
- [ ] A unique index exists on the `slug` column.
- [ ] A foreign key constraint exists on `team_id` referencing `teams`.
- [ ] Creating a content type without a name fails validation with an error on `name`.
- [ ] Creating a content type with a name longer than 255 characters fails validation.
- [ ] Creating a content type with a name but no slug auto-generates the slug from the name.
- [ ] Creating a content type with a duplicate slug (case-insensitive) fails validation.
- [ ] Slug validation rejects uppercase, leading/trailing hyphens, consecutive hyphens, and non-alphanumeric characters (other than hyphens).
- [ ] Creating a content type without a team fails validation.
- [ ] A team can have multiple content types.
- [ ] Destroying a content type that has nodes fails with an error.
- [ ] Destroying a content type with no nodes succeeds.
- [ ] `created_at` and `updated_at` are automatically managed.

## Security Considerations

- Enforce slug uniqueness at both the application and database level (unique index) to prevent race conditions.
- Validate all inputs at the model level regardless of where they originate.

## Accessibility Considerations

No UI in this ticket — accessibility concerns are addressed in CM-03.

## Implementation Notes

### Rails

- Generate a `ContentType` model with a migration.
- Include the `Sluggable` concern (already used by `Node` and `Team`) for slug generation and validation.
- Add `has_many :content_types, dependent: :restrict_with_error` to `Team`.
- Add `has_many :nodes` to `ContentType` (the foreign key on nodes is added in CM-04, but the association can be declared here with `optional: true` awareness).
- Add `add_index :content_types, :slug, unique: true` in the migration.

### Rust (Actix)

- Define a `ContentType` struct.
- Reuse the shared slug generation utility from the node/team implementations.
- Use a database migration for schema setup.
- Enforce the unique index and foreign key in the migration.
