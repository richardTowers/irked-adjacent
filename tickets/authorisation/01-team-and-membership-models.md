# AUTH-01: Team and Membership Models

## Summary

Define the Team and Membership entities. A team is a group of users who collaborate on content. A membership is the join between a user and a team, with a role column for future role-based distinctions. This ticket covers database schema, model validations, and associations only — no UI or authorization enforcement.

## Dependencies

- **CORE-01** — Node model (exists but is not modified in this ticket).
- Authentication must be in place (users exist).

## Requirements

### Team Schema

| Column     | Type     | Constraints                 |
|------------|----------|-----------------------------|
| id         | integer  | Primary key, auto-increment |
| name       | string   | Not null                    |
| slug       | string   | Not null, unique, indexed   |
| created_at | datetime | Auto-managed                |
| updated_at | datetime | Auto-managed                |

### Team Validations

- **name** — required; maximum 255 characters.
- **slug** — required; maximum 255 characters; must match the pattern `^[a-z0-9]+(-[a-z0-9]+)*$` (same slug rules as nodes); must be unique (case-insensitive).

### Team Slug Auto-generation

When a team is created or updated with a name but no slug (blank or nil), the slug is derived from the name using the same rules as node slug generation (CORE-01):

1. Downcase the name.
2. Replace any character that is not a lowercase letter or digit with a hyphen.
3. Collapse consecutive hyphens into one.
4. Strip leading and trailing hyphens.

Slug uniqueness conflicts are validation errors — no silent suffixing.

### Membership Schema

| Column     | Type     | Constraints                              |
|------------|----------|------------------------------------------|
| id         | integer  | Primary key, auto-increment              |
| user_id    | integer  | Not null, foreign key → users, indexed   |
| team_id    | integer  | Not null, foreign key → teams, indexed   |
| role       | string   | Not null, default: "member"              |
| created_at | datetime | Auto-managed                             |
| updated_at | datetime | Auto-managed                             |

A compound unique index must exist on `(user_id, team_id)` — a user can belong to a team only once.

### Membership Validations

- **user** — required; must reference an existing user.
- **team** — required; must reference an existing team.
- **role** — required; must be one of the allowed roles. For now the only allowed role is `"member"`.
- **uniqueness** — a user cannot be added to the same team twice.

### Associations

- A **team** has many memberships and has many users through memberships.
- A **user** has many memberships and has many teams through memberships.
- Destroying a team destroys its memberships.
- Destroying a user destroys their memberships.

## Acceptance Criteria

- [ ] Database table `teams` exists with all columns and constraints listed above.
- [ ] A unique index exists on `teams.slug`.
- [ ] Creating a team without a name fails validation with an error on `name`.
- [ ] Creating a team with a name but no slug auto-generates the slug from the name.
- [ ] Creating a team with a duplicate slug (case-insensitive) fails validation.
- [ ] Team slug validation rejects uppercase, leading/trailing hyphens, consecutive hyphens, and non-alphanumeric characters (other than hyphens).
- [ ] Database table `memberships` exists with all columns and constraints listed above.
- [ ] A compound unique index exists on `(user_id, team_id)`.
- [ ] Creating a membership without a user or team fails validation.
- [ ] Creating a duplicate membership (same user + team) fails validation.
- [ ] The role column defaults to `"member"`.
- [ ] Setting an invalid role value fails validation.
- [ ] Destroying a team cascades to its memberships.
- [ ] Destroying a user cascades to their memberships.
- [ ] A user can belong to multiple teams.
- [ ] A team can have multiple members.

## Security Considerations

- Enforce the compound uniqueness constraint at both the application and database level to prevent race conditions.
- Validate the `role` value against an allowlist — never trust client-provided role values without checking.

## Accessibility Considerations

No UI in this ticket — accessibility concerns are addressed in AUTH-03.

## Implementation Notes

### Rails

- Generate `Team` and `Membership` models with migrations.
- Reuse the slug auto-generation logic from `Node` — consider extracting it into a shared concern (e.g. `Sluggable`), but only if the duplication is exact. Otherwise, duplicate is fine.
- Use `has_many :memberships, dependent: :destroy` on both `Team` and `User`.
- Use `has_many :teams, through: :memberships` on `User` and `has_many :users, through: :memberships` on `Team`.
- Validate role inclusion: `validates :role, inclusion: { in: %w[member] }`.
- Add `add_index :memberships, [:user_id, :team_id], unique: true` in the migration.

### Rust (Actix)

- Define `Team` and `Membership` structs.
- Use a database migration for schema setup.
- Implement slug generation as a shared utility (reuse from node implementation).
- Enforce the compound unique constraint in the migration.
