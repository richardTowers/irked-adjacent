# VERS-01: Branch and Version Schema

## Summary

Introduce a git-like versioning model for nodes. Split the existing `nodes` table into an identity-only entity plus a `versions` table that stores content snapshots, and add a `branches` table for global branch management. This ticket covers schema, models, validations, and data migration only — no UI changes.

## Dependencies

- **CORE-01** — Node model and database schema (the table being restructured).

## Requirements

### Schema Changes to `nodes` Table

Remove the following columns from `nodes`:

| Column       | Action |
|--------------|--------|
| title        | Remove |
| body         | Remove |
| published    | Remove |
| published_at | Remove |

The resulting `nodes` table:

| Column     | Type     | Constraints                 |
|------------|----------|-----------------------------|
| id         | integer  | Primary key, auto-increment |
| slug       | string   | Not null, unique, indexed   |
| created_at | datetime | Auto-managed                |
| updated_at | datetime | Auto-managed                |

Slug becomes **immutable after creation**: once a node is persisted with a slug, the slug cannot be changed. Attempts to modify the slug of a persisted node must fail validation with the message "cannot be changed after creation" on the `slug` field.

### New `branches` Table

| Column     | Type     | Constraints                                |
|------------|----------|--------------------------------------------|
| id         | integer  | Primary key, auto-increment                |
| name       | string   | Not null, unique (case-insensitive), indexed |
| created_at | datetime | Auto-managed                               |
| updated_at | datetime | Auto-managed                               |

Seed data: two branches must be created during the migration:

1. `main` — the default working branch for all content editing.
2. `published` — the reserved branch representing publicly visible content.

### New `versions` Table

| Column            | Type     | Constraints                                                        |
|-------------------|----------|--------------------------------------------------------------------|
| id                | integer  | Primary key, auto-increment                                        |
| node_id           | integer  | Not null, foreign key to `nodes.id`, indexed                       |
| branch_id         | integer  | Not null, foreign key to `branches.id`, indexed                    |
| parent_version_id | integer  | Nullable, self-referencing foreign key to `versions.id`, indexed   |
| source_version_id | integer  | Nullable, self-referencing foreign key to `versions.id`, indexed   |
| title             | string   | Not null                                                           |
| body              | text     | Nullable                                                           |
| commit_message    | text     | Nullable                                                           |
| committed_at      | datetime | Nullable                                                           |
| created_at        | datetime | Auto-managed                                                       |
| updated_at        | datetime | Auto-managed                                                       |

### Indexes and Constraints

- **Unique index on `nodes.slug`** — already exists; retain it.
- **Unique index on `branches.name`** — case-insensitive uniqueness.
- **Foreign key index on `versions.node_id`**.
- **Foreign key index on `versions.branch_id`**.
- **Index on `versions.parent_version_id`**.
- **Index on `versions.source_version_id`**.
- **Partial unique index** on `(node_id, branch_id)` WHERE `committed_at IS NULL` — enforces at most one uncommitted version per node per branch at the database level.
- **Composite index** on `(node_id, branch_id, committed_at)` — supports efficient current-version resolution queries.

### Foreign Key Behaviour

- `versions.node_id` references `nodes.id`. When a node is deleted, all its versions are deleted (cascade).
- `versions.branch_id` references `branches.id`. Branches referenced by versions cannot be deleted (restrict).
- `versions.parent_version_id` references `versions.id`. Set to null if the parent version is deleted (set null).
- `versions.source_version_id` references `versions.id`. Set to null if the source version is deleted (set null).

### Branch Validations

- **name** — required; maximum 50 characters; must match the pattern `^[a-z0-9]+(-[a-z0-9]+)*$` (lowercase letters, digits, and single hyphens between segments — no leading, trailing, or consecutive hyphens); must be unique (case-insensitive).
- The branches named `main` and `published` are **protected**: they cannot be deleted or renamed. Attempting to destroy a protected branch must fail with the error "cannot delete a protected branch" on `base`. Attempting to rename a protected branch must fail with the error "cannot rename a protected branch" on `name`.

### Version Validations

- **title** — required; maximum 255 characters.
- **node** — required (must reference a valid node).
- **branch** — required (must reference a valid branch).
- **body** — optional; no maximum length.
- **commit_message** — must be present (non-blank) when `committed_at` is not null. Must be null when `committed_at` is null. If a commit_message is provided but committed_at is null, validation fails with "cannot be set on an uncommitted version" on `commit_message`. If committed_at is present but commit_message is blank, validation fails with "is required when committing" on `commit_message`.
- **committed_at** — nullable. When set, the version is considered committed and becomes immutable. Attempting to update any field on a committed version (one where `committed_at` is not null) must fail with the error "committed versions are immutable" on `base`. This immutability check applies after the version has been persisted; the initial save that sets `committed_at` is permitted.
- **Uncommitted uniqueness** — at most one uncommitted version (where `committed_at IS NULL`) may exist per `(node_id, branch_id)` pair. Enforced at both the database level (partial unique index) and the application level. Validation error on `base`: "an uncommitted version already exists for this node on this branch".

### Version Lineage Rules

- **parent_version_id** — if present, must reference a version with the same `node_id` and `branch_id` as the current version. It represents the previous version of the same node on the same branch. Validation error if the referenced version has a different node_id or branch_id: "must reference a version of the same node on the same branch" on `parent_version_id`.
- **source_version_id** — if present, must reference a committed version (one with `committed_at IS NOT NULL`) with the same `node_id`. It represents the version from another branch being merged in (used for publish operations and branch forks). Validation error if the referenced version is uncommitted: "must reference a committed version" on `source_version_id`. Validation error if the referenced version has a different node_id: "must reference a version of the same node" on `source_version_id`.
- A version may have both `parent_version_id` and `source_version_id` set (a merge commit — used when publishing).
- A version may have neither set (the first version of a node on a branch).

### Slug Auto-generation (Revised)

Slug auto-generation rules from CORE-01 remain unchanged in their algorithm (downcase, replace non-alphanumeric with hyphens, collapse consecutive hyphens, strip leading/trailing hyphens). However, the input changes:

- **On node creation**: the slug is derived from the `title` of the initial version being created alongside the node. If a slug is explicitly provided, it is used as-is (same as before).
- **After creation**: the slug is immutable. It is never re-generated from updated titles.

Slug uniqueness conflicts remain **validation errors** — the system must not silently append numeric suffixes.

### Creating a Node (Atomic Operation)

Creating a node requires creating the node record and its first version atomically within a single database transaction. The caller provides:

- `title` (required) — stored on the version.
- `slug` (optional) — stored on the node; auto-generated from title if blank.
- `body` (optional) — stored on the version.

The operation must:

1. Begin a transaction.
2. Create the node with the slug (auto-generated from title if blank).
3. Create an uncommitted version on the `main` branch with the provided title and body, `node_id` set to the new node's id, `parent_version_id` and `source_version_id` both null.
4. If any step fails validation, roll back the entire transaction.
5. On success, commit the transaction and return both the node and its initial version.

Do **not** accept `commit_message` or `committed_at` during node creation — the first version is always an uncommitted draft.

### Committing a Version

Committing transitions an uncommitted version to a committed state. The caller provides a `commit_message` (required, non-blank). The operation:

1. Validate that the version is currently uncommitted (`committed_at IS NULL`). If already committed, fail with "version is already committed" on `base`.
2. Set `commit_message` to the provided value.
3. Set `committed_at` to the current timestamp.
4. Save the version. It is now immutable.

A version may be committed even if its title and body are identical to its parent version (empty commits are allowed).

### Publishing a Version (Merge-Commit to `published` Branch)

Publishing takes a committed version from any branch and creates a new version on the `published` branch that copies its content. The source version must be committed. The operation:

1. Validate that the source version is committed (`committed_at IS NOT NULL`). If uncommitted, fail with "cannot publish an uncommitted version" on `base`.
2. Validate that the source version is not already on the `published` branch. Fail with "cannot publish from the published branch" on `base`.
3. Find the latest committed version of the same node on the `published` branch (if any) — this becomes the `parent_version_id`.
4. Create a new committed version on the `published` branch with:
   - `node_id` — same as the source version.
   - `branch_id` — the `published` branch's id.
   - `title` — copied from the source version.
   - `body` — copied from the source version.
   - `parent_version_id` — the latest committed version of this node on the `published` branch (null if first publication).
   - `source_version_id` — the source version's id.
   - `commit_message` — auto-generated: `"Publish from {branch_name}"` where `{branch_name}` is the source version's branch name.
   - `committed_at` — current timestamp.
5. Return the newly created published version.

Direct commits to the `published` branch are **not allowed**. The only way to create versions on the `published` branch is through the publish operation:

- Attempting to create an uncommitted version on the `published` branch must fail with "cannot create uncommitted versions on the published branch" on `base`.
- Attempting to commit a version directly on the `published` branch (other than through the publish mechanism) must fail with "versions on the published branch can only be created by publishing" on `base`.

### Current Version Resolution

To determine the "current" content of a node on a given branch:

1. Look for an uncommitted version for the `(node_id, branch_id)` pair. If one exists, return it.
2. Otherwise, return the latest committed version for the `(node_id, branch_id)` pair, ordered by `committed_at DESC`.
3. If no version exists for the `(node_id, branch_id)` pair, the node does not exist on that branch — return nil/null.

This logic should be encapsulated in a model method or class method (e.g. `Version.current_for(node, branch)` or equivalent).

### Data Migration

Existing nodes must be migrated to the new schema. For each existing node:

1. Preserve the node's `id`, `slug`, `created_at`, and `updated_at`.
2. Create a committed version on the `main` branch with:
   - `title` — from the existing node's title.
   - `body` — from the existing node's body.
   - `commit_message` — `"Migrated from legacy schema"`.
   - `committed_at` — the existing node's `updated_at` timestamp.
   - `parent_version_id` — null.
   - `source_version_id` — null.
3. If the existing node had `published = true`, additionally create a committed version on the `published` branch with:
   - `title` — from the existing node's title.
   - `body` — from the existing node's body.
   - `commit_message` — `"Migrated from legacy schema"`.
   - `committed_at` — the existing node's `published_at` timestamp (or `updated_at` if `published_at` is null).
   - `parent_version_id` — null.
   - `source_version_id` — the id of the `main` branch version created in step 2.
4. After all nodes are migrated, drop the `title`, `body`, `published`, and `published_at` columns from `nodes`.

The migration must be reversible. The reverse migration must:

1. Re-add the removed columns to `nodes`.
2. For each node, populate `title` and `body` from its latest committed version on the `main` branch.
3. Set `published = true` if the node has any version on the `published` branch; `false` otherwise.
4. Set `published_at` from the latest committed version's `committed_at` on the `published` branch (null if unpublished).
5. Drop the `versions` and `branches` tables.

## Acceptance Criteria

### Schema

- [ ] The `nodes` table retains only `id`, `slug`, `created_at`, and `updated_at` columns.
- [ ] The `nodes.slug` column retains its NOT NULL constraint and unique index.
- [ ] The `branches` table exists with `id`, `name`, `created_at`, and `updated_at` columns.
- [ ] A unique index exists on `branches.name`.
- [ ] The `versions` table exists with all columns listed in the schema.
- [ ] Foreign key indexes exist on `versions.node_id`, `versions.branch_id`, `versions.parent_version_id`, and `versions.source_version_id`.
- [ ] A partial unique index exists on `(node_id, branch_id)` where `committed_at IS NULL`.
- [ ] A composite index exists on `(node_id, branch_id, committed_at)`.
- [ ] Seed data includes branches named `main` and `published`.

### Node Validations

- [ ] Creating a node with a valid title auto-generates a slug and creates an uncommitted version on the `main` branch.
- [ ] The slug is immutable after creation — updating the slug of a persisted node fails validation with "cannot be changed after creation".
- [ ] Slug validation rules from CORE-01 still apply (format, length, uniqueness).
- [ ] Deleting a node cascades to delete all its versions.

### Branch Validations

- [ ] Creating a branch without a name fails validation with an error on `name`.
- [ ] Creating a branch with a name longer than 50 characters fails validation.
- [ ] Creating a branch with invalid format (uppercase, spaces, consecutive hyphens) fails validation.
- [ ] Creating a branch with a duplicate name (case-insensitive) fails validation.
- [ ] Deleting the `main` branch fails with "cannot delete a protected branch".
- [ ] Deleting the `published` branch fails with "cannot delete a protected branch".
- [ ] Renaming the `main` branch fails with "cannot rename a protected branch".
- [ ] Renaming the `published` branch fails with "cannot rename a protected branch".

### Version Validations

- [ ] Creating a version without a title fails validation.
- [ ] Creating a version with a title longer than 255 characters fails validation.
- [ ] Creating a version without a node fails validation.
- [ ] Creating a version without a branch fails validation.
- [ ] Setting commit_message without committed_at fails validation.
- [ ] Setting committed_at without commit_message fails validation.
- [ ] A committed version cannot be modified — attempting to update any attribute fails with "committed versions are immutable".
- [ ] Only one uncommitted version may exist per `(node_id, branch_id)` — the second attempt fails validation.
- [ ] The partial unique index enforces the uncommitted uniqueness constraint at the database level.

### Version Lineage

- [ ] `parent_version_id` must reference a version with the same `node_id` and `branch_id`, or be null.
- [ ] `source_version_id` must reference a committed version with the same `node_id`, or be null.

### Node Creation

- [ ] Creating a node atomically creates both the node and an uncommitted version on `main`.
- [ ] If the version fails validation, the node is not created (transaction rolls back).
- [ ] If the node fails validation (e.g. duplicate slug), no version is created.
- [ ] Slug auto-generation derives the slug from the version's title.

### Committing

- [ ] Committing an uncommitted version sets `committed_at` and `commit_message`, making it immutable.
- [ ] Committing an already-committed version fails with "version is already committed".
- [ ] Committing with a blank commit_message fails validation.
- [ ] Empty commits (no content changes from parent) are allowed.

### Publishing

- [ ] Publishing a committed version creates a new committed version on the `published` branch.
- [ ] The published version copies title and body from the source version.
- [ ] The published version's `source_version_id` points to the source version.
- [ ] The published version's `parent_version_id` points to the previous published version of the same node (or null).
- [ ] The published version's commit_message is `"Publish from {branch_name}"`.
- [ ] Publishing an uncommitted version fails with "cannot publish an uncommitted version".
- [ ] Publishing a version already on the `published` branch fails with "cannot publish from the published branch".
- [ ] Creating an uncommitted version on the `published` branch fails with "cannot create uncommitted versions on the published branch".

### Current Version Resolution

- [ ] For a `(node, branch)` pair with an uncommitted version, `current_for` returns the uncommitted version.
- [ ] For a `(node, branch)` pair with only committed versions, `current_for` returns the latest by `committed_at`.
- [ ] For a `(node, branch)` pair with no versions, `current_for` returns nil/null.

### Data Migration

- [ ] Existing nodes retain their `id`, `slug`, `created_at`, and `updated_at`.
- [ ] Each existing node has a committed version on the `main` branch with its original title and body.
- [ ] Nodes that were published also have a committed version on the `published` branch with `source_version_id` pointing to the `main` version.
- [ ] The migration is reversible.
- [ ] After migration, the `title`, `body`, `published`, and `published_at` columns no longer exist on the `nodes` table.

## Security Considerations

- **Database-level constraints:** The partial unique index on `(node_id, branch_id)` WHERE `committed_at IS NULL` prevents race conditions that could create duplicate uncommitted versions. Do not rely solely on application-level checks.
- **Immutability enforcement:** Committed version immutability must be enforced at the model level regardless of how the update is triggered — not just through controller-level guards.
- **Transaction safety:** Node creation (node + first version) must be wrapped in a database transaction to prevent orphaned nodes (nodes with no versions) or orphaned versions (versions with no node).
- **Foreign key constraints:** Use database-level foreign keys to maintain referential integrity. Do not rely solely on application-level association validations.
- **Mass assignment protection:** The `committed_at` and `commit_message` fields on Version must not be directly settable through bulk parameter assignment. They should only be set through dedicated commit and publish operations.
- **Protected branch enforcement:** The restriction on the `published` branch (no direct commits, no uncommitted versions) must be enforced at the model level, not the controller level.

## Accessibility Considerations

No UI in this ticket — accessibility concerns will be addressed in subsequent tickets that add versioning UI (VERS-02 and beyond).

## Implementation Notes

### Rails

- Create a migration that:
  1. Creates the `branches` table.
  2. Creates the `versions` table with all indexes and foreign keys.
  3. Seeds the `main` and `published` branches.
  4. Migrates existing node data into versions.
  5. Removes `title`, `body`, `published`, and `published_at` from `nodes`.
- Use `add_index :versions, [:node_id, :branch_id], unique: true, where: "committed_at IS NULL", name: "index_versions_uncommitted_unique"` for the partial unique index.
- Generate a `Branch` model with validations and a `protected?` method that checks if the name is in `%w[main published]`.
- Generate a `Version` model with:
  - `belongs_to :node`, `belongs_to :branch`, `belongs_to :parent_version, class_name: "Version", optional: true`, `belongs_to :source_version, class_name: "Version", optional: true`.
  - A custom validation for commit_message/committed_at consistency.
  - A custom validation for immutability using `committed_at_in_database` (or `committed_at_was`) to detect whether the record was already committed before the current change.
  - Scopes: `committed` (`where.not(committed_at: nil)`) and `uncommitted` (`where(committed_at: nil)`).
  - A class method `current_for(node, branch)` that returns the uncommitted version or the latest committed version.
- Modify the `Node` model:
  - Remove title, body, published validations and callbacks (`generate_slug_from_title` stays but is adapted; `set_published_at` is removed).
  - Add `has_many :versions, dependent: :destroy`.
  - Add slug immutability validation: `errors.add(:slug, "cannot be changed after creation") if slug_changed? && persisted?`.
  - Add a class method or concern for atomic node+version creation wrapping `Node.transaction { ... }`.
- For the reversible migration, use `reversible do |dir|` with separate `dir.up` and `dir.down` blocks, or separate `up` and `down` methods instead of `change`.

### Rust (Actix)

- Create SQL migrations for:
  1. `branches` table creation and seed data.
  2. `versions` table creation with all indexes and foreign keys.
  3. Existing node data migration.
  4. Column removal from `nodes`.
- Note: SQLite partial index syntax is `CREATE UNIQUE INDEX ... ON versions (node_id, branch_id) WHERE committed_at IS NULL;`.
- Define `Branch` and `Version` structs with `sqlx::FromRow`.
- Implement validation logic in dedicated methods, following the existing `ValidationErrors` pattern from the `Node` model.
- Implement slug immutability by comparing the slug before and after in the update path.
- Wrap node+version creation in a SQLx transaction (`pool.begin()` ... `tx.commit()`).
- Implement `Version::current_for(pool, node_id, branch_id)` as a query: first look for `committed_at IS NULL`, then fall back to `ORDER BY committed_at DESC LIMIT 1`.
- The existing `generate_slug` function can be reused as-is for the new creation flow.
