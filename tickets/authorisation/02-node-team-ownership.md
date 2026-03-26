# AUTH-02: Node Team Ownership

## Summary

Associate nodes with teams. Every node belongs to exactly one team. This is the foundation for authorization — knowing which team owns a node tells us who can edit it. This ticket covers the schema change and model-level association only; enforcement is in AUTH-04.

## Dependencies

- **CORE-01** — Node model exists.
- **AUTH-01** — Team model exists.

## Requirements

### Schema Change

Add a `team_id` column to the `nodes` table:

| Column  | Type    | Constraints                            |
|---------|---------|----------------------------------------|
| team_id | integer | Nullable, foreign key → teams, indexed |

The column is **nullable** to allow a migration path for existing data. Nodes without a team are considered "unassigned" and are not editable by anyone until assigned to a team.

### Association

- A **node** belongs to a team (optional for migration purposes, but required for new nodes — see validation below).
- A **team** has many nodes.
- Destroying a team does **not** cascade to its nodes — instead, team deletion should be blocked if the team still has nodes. This prevents accidental content loss.

### Validation

- **New nodes** must have a `team_id` — it is required on creation.
- **Existing nodes** with a null `team_id` are permitted (they were created before this feature existed) but cannot be edited until assigned to a team.

### Scoping

- Provide a way to query "all nodes belonging to a given team" efficiently (the foreign key index covers this).
- Provide a way to query "all teams the current user is a member of" and from that, "all nodes the current user can access".

## Acceptance Criteria

- [ ] The `nodes` table has a `team_id` column with a foreign key constraint to `teams`.
- [ ] An index exists on `nodes.team_id`.
- [ ] A node can be associated with a team.
- [ ] Querying nodes by team returns only that team's nodes.
- [ ] Creating a new node without a `team_id` fails validation.
- [ ] Existing nodes with null `team_id` remain valid (not retroactively broken by the migration).
- [ ] Destroying a team that still has nodes is prevented (returns an error).
- [ ] A node's team can be reassigned by updating `team_id`.

## Security Considerations

- The `team_id` on a node must be validated against teams the current user is a member of — this is enforced in AUTH-04, not here, but the model should not blindly accept any `team_id`.
- Add `team_id` to the permitted parameters for node creation and update, but authorization checks (AUTH-04) must verify the user has access to the specified team.

## Accessibility Considerations

No direct UI in this ticket. The team selector UI for node creation/editing is part of AUTH-04.

## Implementation Notes

### Rails

- Generate a migration: `add_reference :nodes, :team, foreign_key: true, null: true, index: true`.
- Add `belongs_to :team, optional: true` on `Node` (optional to allow null for existing records).
- Add a custom validation that requires `team_id` for new records: e.g. `validates :team_id, presence: true, on: :create` — but be careful, this should also apply on update for records that already have a team. Consider `validates :team_id, presence: true, if: -> { new_record? || team_id_was.present? }`.
- Add `has_many :nodes, dependent: :restrict_with_error` on `Team`.

### Rust (Actix)

- Add a migration to alter the `nodes` table.
- Update the `Node` struct to include an optional `team_id` field.
- Enforce the new-node requirement in the creation handler.
- Use a foreign key constraint with `ON DELETE RESTRICT`.
