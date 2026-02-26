# VERS-05: Version History

## Summary

Add the ability to view the version history of a node on a given branch. This provides a chronological log of commits, the ability to view the content of any past version, and the ability to revert to a previous version by creating a new draft from it.

## Dependencies

- **VERS-01** — Branch and version schema (version records and lineage).
- **VERS-02** — Commit workflow (committed versions to display).
- **VERS-04** — Branch management (history is scoped to the selected branch).

## Requirements

### Routes

| Method | Path                                       | Action         | Notes                           |
|--------|--------------------------------------------|----------------|---------------------------------|
| GET    | /admin/content/:id/history                 | History Index  | **New** — version list          |
| GET    | /admin/content/:id/versions/:version_id    | Version Show   | **New** — view a past version   |
| POST   | /admin/content/:id/versions/:version_id/revert | Revert     | **New** — create draft from version |

### History Page

`GET /admin/content/:id/history` displays the version history of a node on the selected branch.

- Page heading: "History for {node_title}" where `{node_title}` is the title of the current version on the selected branch.
- Display committed versions on the selected branch in reverse chronological order (`committed_at DESC`).
- If an uncommitted version exists on the selected branch, display it at the top of the list, clearly marked as "Current draft".
- Each version entry shows:
  - **Commit message** — the version's `commit_message`, or "Uncommitted draft" for the uncommitted version.
  - **Committed at** — the `committed_at` timestamp, formatted as a human-readable date and time, or "Not yet committed" for the uncommitted version.
  - **Source** — if `source_version_id` is present, display "Merged from {source_branch_name}" to indicate a merge commit (e.g. a fork from another branch, or a publish merge). Otherwise, blank.
  - **View link** — links to the version show page (`/admin/content/:id/versions/:version_id`).
- When no versions exist (should not happen for a valid node, but as a guard): display "No version history."
- A "Back to Node" link pointing to `/admin/content/:id`.

### Version Show Page

`GET /admin/content/:id/versions/:version_id` displays the full content of a specific version.

- Page heading: the version's `commit_message`, or "Uncommitted draft" for uncommitted versions.
- Display:
  - **Title** — the version's title.
  - **Body** — the version's body.
  - **Committed at** — timestamp or "Not yet committed".
  - **Commit message** — or "None" for uncommitted.
  - **Parent version** — link to the parent version if `parent_version_id` is set, otherwise "None (initial version)".
  - **Source version** — if `source_version_id` is set, link to the source version with the source branch name, otherwise "None".
- Action links:
  - "Back to History" — links to `/admin/content/:id/history`.
  - "Back to Node" — links to `/admin/content/:id`.
  - "Revert to This Version" — a form button, displayed only for committed versions (not for the current uncommitted draft, and not when viewing on the `published` branch). See Revert section below.

### Validation

- The `:id` parameter must be a valid node id. Return HTTP 404 for non-existent or non-integer values.
- The `:version_id` parameter must be a valid version id that belongs to the given node. Return HTTP 404 if:
  - The version does not exist.
  - The version belongs to a different node.
  - The version_id is not a valid integer.
- The version does **not** need to belong to the currently selected branch — users may follow links to versions on other branches (e.g. source versions from merge commits). The history list filters by branch, but the version show page does not.

### Revert Action

`POST /admin/content/:id/versions/:version_id/revert` creates a new uncommitted draft on the selected branch with the content of the specified version.

The operation:

1. Validate the node and version exist, and the version belongs to the node.
2. Validate the selected branch is not `published` (read-only). If it is, redirect with alert: "Cannot revert on the published branch."
3. If an uncommitted version already exists on the selected branch for this node, **update it** with the title and body from the target version.
4. If no uncommitted version exists, **create one** on the selected branch with:
   - `title` and `body` — copied from the target version.
   - `parent_version_id` — the latest committed version on the selected branch (may be null if no committed versions exist on this branch).
   - `source_version_id` — the target version being reverted to (this records lineage — "this draft was derived from that version").
5. Redirect to the show page (`/admin/content/:id`) with flash notice: "Reverted to version from {committed_at_timestamp}."

The revert action does **not** commit the reverted content. It creates a draft that the user can review, modify, and then commit with their own message. This prevents accidental publication of old content.

Failure cases:

- **Node not found:** HTTP 404.
- **Version not found or wrong node:** HTTP 404.
- **Published branch selected:** Redirect with alert.
- **Version is the current uncommitted draft on this branch:** Redirect with alert: "Cannot revert to the current draft." (Reverting to the current state is a no-op and likely a mistake.)

### Show Page Link

The node show page (from VERS-02) gains a "History" link pointing to `/admin/content/:id/history`. This link is displayed alongside "Edit Node" and "Delete Node".

## Acceptance Criteria

### History Page

- [ ] `GET /admin/content/:id/history` returns HTTP 200 and displays the version history.
- [ ] Committed versions are listed in reverse chronological order by `committed_at`.
- [ ] Each version shows its commit message, committed_at timestamp, and source information.
- [ ] If an uncommitted version exists, it appears at the top marked as "Current draft".
- [ ] Each version has a "View" link to its version show page.
- [ ] A "Back to Node" link is present.
- [ ] `GET /admin/content/999/history` returns HTTP 404.
- [ ] `GET /admin/content/abc/history` returns HTTP 404.

### Version Show Page

- [ ] `GET /admin/content/:id/versions/:version_id` returns HTTP 200 and displays the version's content.
- [ ] The page shows the version's title, body, commit message, committed_at, parent, and source.
- [ ] Parent and source versions are displayed as links when present.
- [ ] "Revert to This Version" is displayed for committed versions.
- [ ] "Revert to This Version" is not displayed for uncommitted versions.
- [ ] "Revert to This Version" is not displayed when on the `published` branch.
- [ ] The page works for versions on any branch, not just the selected branch.
- [ ] `GET /admin/content/:id/versions/999` (wrong version) returns HTTP 404.
- [ ] `GET /admin/content/:id/versions/:version_id` where version belongs to a different node returns HTTP 404.

### Revert

- [ ] `POST /admin/content/:id/versions/:version_id/revert` creates an uncommitted draft with the target version's content.
- [ ] If an uncommitted draft already exists, it is updated with the target version's content.
- [ ] The new draft's `source_version_id` points to the target version.
- [ ] The revert does not commit — the content is left as an uncommitted draft.
- [ ] After reverting, redirect to the show page with flash "Reverted to version from {timestamp}."
- [ ] Reverting on the `published` branch redirects with alert "Cannot revert on the published branch."
- [ ] Reverting to the current uncommitted draft redirects with alert "Cannot revert to the current draft."
- [ ] `POST /admin/content/999/versions/1/revert` returns HTTP 404.

### Show Page Link

- [ ] The node show page includes a "History" link to `/admin/content/:id/history`.

## Security Considerations

- **CSRF protection:** The revert form must include a CSRF token. The revert action must verify it.
- **Parameter validation:** Both `:id` and `:version_id` must be validated as positive integers. The version must belong to the specified node — never allow viewing or reverting a version from a different node.
- **XSS prevention:** All version content (title, body, commit message) must be HTML-escaped when rendered.
- **Information scoping:** The history page filters by the selected branch. The version show page allows cross-branch viewing (for following lineage links), but does not expose a way to enumerate all versions across all branches for a node.

## Accessibility Considerations

- The history list uses semantic HTML — either a `<table>` with proper `<thead>`/`<th scope="col">` elements, or a description list (`<dl>`) depending on layout.
- Each version entry's "View" link has accessible text — if the link text is generic (e.g. "View"), use `aria-label` to include the commit message or timestamp for uniqueness.
- The "Revert to This Version" button is a `<button>` inside a `<form>`, not a styled link.
- The "Current draft" indicator at the top of the history list is conveyed through text, not colour alone.
- Parent and source version links are descriptive — e.g. "View parent version" rather than just the version id.
- Flash messages after revert follow the standard patterns (`role="status"` for notices, `role="alert"` for errors).
- The version show page uses a definition list (`<dl>/<dt>/<dd>`) for metadata display, consistent with the node show page pattern from CORE-02.

## Implementation Notes

### Rails

- Add routes:
  ```ruby
  namespace :admin do
    resources :content, only: [] do
      get 'history', on: :member
      resources :versions, only: [:show], module: 'content' do
        post 'revert', on: :member
      end
    end
  end
  ```
  Alternatively, define explicit routes if the nested resource structure is too complex:
  ```ruby
  get '/admin/content/:id/history', to: 'admin/content#history'
  get '/admin/content/:id/versions/:version_id', to: 'admin/versions#show'
  post '/admin/content/:id/versions/:version_id/revert', to: 'admin/versions#revert'
  ```
- Add `history` action to `Admin::ContentController` (or a separate `Admin::VersionsController`).
- Version scoping for the history page: `node.versions.where(branch: current_branch).committed.order(committed_at: :desc)`, prepended with the uncommitted version if it exists.
- For the version show page, load via `node.versions.find(params[:version_id])` — this scopes to the node automatically and raises `RecordNotFound` if the version belongs to a different node.
- Revert logic can be a method on `Version` or a service object: `Version.revert_to(target_version, branch:)`.
- Add `includes(:branch, :source_version)` to history queries to avoid N+1 when displaying source branch names.

### Rust (Actix)

- Add route handlers for history, version show, and revert.
- History query: `SELECT * FROM versions WHERE node_id = ? AND branch_id = ? AND committed_at IS NOT NULL ORDER BY committed_at DESC`, plus a separate query for the uncommitted version.
- Version show: `SELECT * FROM versions WHERE id = ? AND node_id = ?` — the node_id check prevents cross-node access.
- Revert handler: find or create uncommitted version on the current branch, copy content from target.
- Add the "History" link to the node show template.
- Use joins or separate queries to resolve source branch names for merge commits.
