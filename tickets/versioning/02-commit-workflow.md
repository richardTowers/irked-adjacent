# VERS-02: Commit Workflow

## Summary

Update the admin interface to work with the versioned node model introduced in VERS-01. Replace direct node editing with version-based draft editing, and add the ability to commit changes with a message. All operations in this ticket target the `main` branch implicitly — branch selection is introduced in a later ticket.

## Dependencies

- **VERS-01** — Branch and version schema (new tables and model layer).
- **CORE-02** through **CORE-05** — Existing admin UI being updated.

## Requirements

### Routes

| Method     | Path                       | Action  | Change     |
|------------|----------------------------|---------|------------|
| GET        | /admin/content             | Index   | Updated    |
| GET        | /admin/content/new         | New     | Updated    |
| POST       | /admin/content             | Create  | Updated    |
| GET        | /admin/content/:id         | Show    | Updated    |
| GET        | /admin/content/:id/edit    | Edit    | Updated    |
| PATCH/PUT  | /admin/content/:id         | Update  | Updated    |
| DELETE     | /admin/content/:id         | Destroy | Unchanged  |
| POST       | /admin/content/:id/commit  | Commit  | **New**    |

### Index Page

- Display all nodes in a table, ordered by `nodes.updated_at DESC`.
- Table columns:
  - **Title** — from the current version on the `main` branch (see VERS-01 current version resolution). Links to the show page.
  - **Slug** — from the node.
  - **Status** — one of:
    - "Draft" if the node has an uncommitted version on `main`.
    - "Committed" if the node has only committed versions on `main`.
- When no nodes exist, display the message: "No nodes yet."
- Each row links to the node's show page.

### New Node Form

- Page heading: "New Node".
- Form fields:
  - **Title** — text input, required.
  - **Slug** — text input, optional (auto-generated from title if left blank).
  - **Body** — textarea, optional.
- The **Published** checkbox from CORE-03 is removed. Publishing is a separate workflow (VERS-03).
- Submit button with the text "Create Node".
- Cancel link with the text "Cancel" pointing to `/admin/content`.

### Create Action

- On valid submission:
  1. Create the node and its first uncommitted version on `main` atomically (per VERS-01).
  2. Redirect to the show page (`/admin/content/:id`).
  3. Display flash message: "Node was successfully created."
- On invalid submission:
  - Re-render the form with all previously entered values preserved.
  - Display validation error messages.
  - HTTP status 422.

### Mass Assignment Protection (Create)

- Accept only: `title`, `slug`, `body`.
- Reject or ignore all other parameters. The `published`, `published_at`, `commit_message`, and `committed_at` fields must never be settable through the create form.

### Show Page

- Display the following from the node and its current version on `main`:
  - **Title** — from the current version.
  - **Slug** — from the node.
  - **Body** — from the current version.
  - **Status** — one of:
    - "Draft" if the current version is uncommitted.
    - "Committed" if the current version is committed, with the commit message and committed_at timestamp displayed.
- Action links:
  - "Edit Node" — links to the edit page.
  - "Delete Node" — delete form (per CORE-05, unchanged).
  - "Back to Nodes" — links to the index page.

#### Commit Form (Conditional)

When the current version on `main` is uncommitted, the show page displays a commit form:

- A text input for the commit message, with label "Commit message".
- A submit button with the text "Commit".
- The form submits `POST` to `/admin/content/:id/commit`.

When the current version is already committed, the commit form is **not displayed**. Instead, show the commit message and timestamp of the latest committed version.

### Edit Page

- Page heading: "Edit Node".
- Form fields:
  - **Title** — text input, required. Pre-filled from the current version on `main`.
  - **Slug** — displayed as **read-only text** (not an editable input). Slug is immutable after creation.
  - **Body** — textarea, optional. Pre-filled from the current version on `main`.
- The edit form loads its data from the current version (uncommitted if one exists, otherwise the latest committed version). Visiting the edit page does **not** create an uncommitted version — it is side-effect-free.
- Submit button with the text "Save Draft".
- Cancel link with the text "Cancel" pointing to `/admin/content/:id`.

### Update Action (Save Draft)

- On valid submission:
  - If an uncommitted version exists on `main` for this node: update its `title` and `body`.
  - If no uncommitted version exists: create a new uncommitted version on `main` with the submitted `title` and `body`, and `parent_version_id` set to the latest committed version on `main`.
  - Redirect to the show page (`/admin/content/:id`).
  - Display flash message: "Draft was successfully saved."
- On invalid submission:
  - Re-render the edit form with all previously entered values preserved.
  - Display validation error messages.
  - HTTP status 422.

### Mass Assignment Protection (Update)

- Accept only: `title`, `body`.
- Reject or ignore all other parameters. The `slug`, `commit_message`, `committed_at`, `branch_id`, `node_id`, `parent_version_id`, and `source_version_id` fields must never be settable through the update form.

### Commit Action

- `POST /admin/content/:id/commit` transitions the current uncommitted version on `main` to committed.
- Accepts parameter: `commit_message` (required, non-blank).
- On success:
  - Commit the version (per VERS-01 committing logic).
  - Redirect to the show page (`/admin/content/:id`).
  - Display flash message: "Version was successfully committed."
- On failure — no uncommitted version:
  - Redirect to the show page.
  - Display flash message: "No uncommitted changes to commit." (as `alert`, not `notice`).
- On failure — blank commit message:
  - Redirect to the show page.
  - Display flash message: "Commit message can't be blank." (as `alert`).
- On failure — node not found:
  - Return HTTP 404.

### Mass Assignment Protection (Commit)

- Accept only: `commit_message`.
- Reject or ignore all other parameters.

### Delete Action

- Unchanged from CORE-05. Deleting a node cascades to all its versions (enforced by the foreign key constraint from VERS-01).
- Flash message remains: "Node was successfully deleted."
- Confirmation dialog remains: "Are you sure you want to delete this node? This action cannot be undone."

### Parameter Validation

- The `:id` parameter must be validated as a positive integer. Non-integer values result in a 404 response.
- This applies to all actions that take `:id`: show, edit, update, destroy, commit.

## Acceptance Criteria

### Index Page

- [ ] The index page displays node titles from the current version on `main`.
- [ ] The index page displays each node's slug.
- [ ] The index page displays "Draft" for nodes with uncommitted versions.
- [ ] The index page displays "Committed" for nodes with only committed versions.
- [ ] Nodes are ordered by `updated_at DESC`.
- [ ] When no nodes exist, the message "No nodes yet." is displayed.

### Create

- [ ] `GET /admin/content/new` returns HTTP 200 and displays the new-node form.
- [ ] The form has fields for title, slug, and body — but no published checkbox.
- [ ] Submitting the form with a valid title creates a node and an uncommitted version on `main`.
- [ ] After successful creation, redirect to the show page with flash "Node was successfully created."
- [ ] Submitting with a blank title re-renders the form with an error on the title field.
- [ ] On validation failure, previously entered values are preserved in the form.
- [ ] On validation failure, the response status is 422.
- [ ] Leaving the slug blank auto-generates it from the title (per VERS-01 rules).
- [ ] Providing an explicit slug uses that value.
- [ ] Submitting with a duplicate slug re-renders with an error on slug.
- [ ] Only title, slug, and body are accepted — other parameters are ignored.
- [ ] The cancel link navigates to `/admin/content`.

### Show Page

- [ ] `GET /admin/content/:id` returns HTTP 200 and displays the node's content from the current version on `main`.
- [ ] When the current version is uncommitted, the status reads "Draft".
- [ ] When the current version is committed, the status reads "Committed" with the message and timestamp.
- [ ] When the current version is uncommitted, a commit form is displayed with a message field and "Commit" button.
- [ ] When the current version is committed, no commit form is displayed.
- [ ] The page has links for "Edit Node", "Delete Node", and "Back to Nodes".
- [ ] `GET /admin/content/999` (non-existent id) returns HTTP 404.
- [ ] `GET /admin/content/abc` (non-integer id) returns HTTP 404.

### Edit / Save Draft

- [ ] `GET /admin/content/:id/edit` returns HTTP 200 and displays the edit form.
- [ ] The title field is pre-filled from the current version on `main`.
- [ ] The body field is pre-filled from the current version on `main`.
- [ ] The slug is displayed as read-only text, not an editable input.
- [ ] Visiting the edit page does not create an uncommitted version (side-effect-free).
- [ ] Saving when no uncommitted version exists creates one with `parent_version_id` pointing to the latest committed version.
- [ ] Saving when an uncommitted version exists updates it in place.
- [ ] After saving, redirect to the show page with flash "Draft was successfully saved."
- [ ] Saving with a blank title re-renders the form with an error on title.
- [ ] On validation failure, previously entered values are preserved.
- [ ] On validation failure, the response status is 422.
- [ ] Only title and body are accepted — other parameters are ignored.
- [ ] The submit button reads "Save Draft".
- [ ] The cancel link navigates to `/admin/content/:id`.

### Commit

- [ ] `POST /admin/content/:id/commit` with a valid commit message commits the uncommitted version and redirects to the show page.
- [ ] After successful commit, flash message reads "Version was successfully committed."
- [ ] The committed version is now immutable.
- [ ] Committing with a blank commit message redirects to the show page with alert "Commit message can't be blank."
- [ ] Committing when no uncommitted version exists redirects with alert "No uncommitted changes to commit."
- [ ] `POST /admin/content/999/commit` returns HTTP 404.
- [ ] `POST /admin/content/abc/commit` returns HTTP 404.
- [ ] Only commit_message is accepted — other parameters are ignored.

### Delete

- [ ] Deletion still works per CORE-05 — deletes the node and cascades to all versions.
- [ ] Flash message and confirmation dialog are unchanged.

## Security Considerations

- **Mass assignment protection:** Each action has a strictly limited parameter whitelist. The create action must not accept `commit_message`, `committed_at`, or any version metadata. The update action must not accept `slug` (immutable), `commit_message`, or `committed_at`. The commit action must only accept `commit_message`.
- **CSRF protection:** All forms (create, update, commit, delete) must include CSRF tokens. All mutating actions must verify them.
- **Parameter validation:** The `:id` parameter must be validated on all actions. Never pass raw user input directly to queries.
- **XSS prevention:** All user-provided content (title, body, slug, commit message) must be properly escaped when rendered in HTML.

## Accessibility Considerations

- Every form field has a `<label>` element with a `for` attribute matching the input's `id`.
- The title field on the new-node form has the `required` attribute set.
- When validation errors occur:
  - Each error message is associated with its field via `aria-describedby`.
  - An error summary appears near the top of the form with `role="alert"` so screen readers announce it immediately.
  - Invalid fields have `aria-invalid="true"` set.
- Flash success messages are in a container with `role="status"` or `aria-live="polite"`.
- Flash error/alert messages are in a container with `role="alert"`.
- The commit form on the show page follows the same accessibility patterns as other forms (label, describedby, etc.).
- The slug on the edit page, displayed as read-only text, should be clearly distinguishable from editable fields (e.g. rendered as plain text, not a disabled input).
- The "Draft" / "Committed" status on the index and show pages uses semantic markup — not colour alone — to convey meaning.

## Implementation Notes

### Rails

- Update `Admin::ContentController`:
  - `create`: Use the atomic node+version creation method from VERS-01. Strong params: `params.require(:node).permit(:title, :slug, :body)`.
  - `show`: Load the node, then `Version.current_for(node, main_branch)` to get the current version.
  - `edit`: Same loading as show — read from current version, do not create an uncommitted version.
  - `update`: Strong params: `params.require(:node).permit(:title, :body)`. Find or create uncommitted version. If creating, set `parent_version_id` to latest committed.
  - `commit`: New action. Strong params: `params.require(:commit).permit(:commit_message)`. Call the commit operation from VERS-01.
  - `index`: Load all nodes with their current version title on `main`. Consider using `includes` or a join to avoid N+1 queries, but correctness over performance.
  - `destroy`: Unchanged — `node.destroy` cascades to versions.
- Add route: `post '/admin/content/:id/commit', to: 'admin/content#commit', as: :commit_admin_content`.
- Update views:
  - `index.html.erb`: Display title from version, add status column.
  - `show.html.erb`: Display version content, add commit form (conditionally rendered).
  - `_form.html.erb`: Remove `published` checkbox, remove `slug` field from edit context (or render read-only). Consider splitting into `_new_form` and `_edit_form` if the differences are significant.
  - `edit.html.erb`: Display slug as text rather than a form input.
- Flash alerts (errors) should be rendered with `role="alert"` in the layout, distinct from `role="status"` used for notices.

### Rust (Actix)

- Update route handlers in the content admin module:
  - `create_node`: Use the atomic node+version creation within a transaction. Only accept `title`, `slug`, `body` from the form.
  - `show_node`: Load node + `Version::current_for(pool, node_id, main_branch_id)`.
  - `edit_node`: Same loading as show — no side effects.
  - `update_node`: Find or create uncommitted version. Only accept `title`, `body`.
  - `commit_node`: New handler for `POST /admin/content/:id/commit`. Accept `commit_message`. Call `Version::commit()`.
  - `delete_node`: Unchanged.
  - `list_nodes`: Load nodes with current version titles. Consider a single query with a join or subquery.
- Add the `/admin/content/{id}/commit` route to the router.
- Update Tera/Askama templates to match the view changes described above.
- Flash alert messages (for errors) should be distinguished from notice messages in the template — use separate flash categories or a flag.
