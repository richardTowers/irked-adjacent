# VERS-04: Branch Management

## Summary

Add the ability to create, list, switch between, and delete branches. Introduce a session-based branch selector in the admin interface so that all content operations — viewing, editing, committing, and publishing — target the selected branch. This ticket also updates the existing content workflows from VERS-02 and VERS-03 to be branch-aware.

## Dependencies

- **VERS-01** — Branch and version schema.
- **VERS-02** — Commit workflow (updated to be branch-aware).
- **VERS-03** — Publishing workflow (updated to publish from the selected branch).

## Requirements

### Routes

| Method | Path                        | Action        | Notes                  |
|--------|-----------------------------|---------------|------------------------|
| GET    | /admin/branches             | Index         | **New** — list all     |
| GET    | /admin/branches/new         | New           | **New** — create form  |
| POST   | /admin/branches             | Create        | **New**                |
| DELETE | /admin/branches/:id         | Destroy       | **New**                |
| POST   | /admin/switch-branch        | Switch        | **New** — set session  |

### Branch Selector (Admin Layout)

A branch selector is displayed in the admin layout on every admin page:

- Shows the name of the currently selected branch.
- Provides a mechanism to switch to any other branch (e.g. a dropdown of branch names, each submitting a form to `/admin/switch-branch`).
- The selector always shows all branches, ordered alphabetically, with `main` listed first.
- Switching branches submits `POST /admin/switch-branch` with the `branch_id` and redirects back to the referring page (or `/admin/content` if no referrer).

### Session-Based Branch Selection

- The currently selected branch is stored in the user's session as `current_branch_id`.
- If no branch is selected in the session (first visit), default to the `main` branch.
- If the session references a branch that no longer exists (e.g. it was deleted), fall back to `main`.
- All content operations — index, show, edit, update, commit, publish — use the session's current branch instead of hardcoding `main`.

### Branch List Page

`GET /admin/branches` displays all branches in a table:

- Page heading: "Branches".
- Table columns:
  - **Name** — the branch name.
  - **Protected** — "Yes" for `main` and `published`; blank otherwise.
  - **Created** — the `created_at` timestamp.
- Each non-protected branch has a "Delete" button (a form with `DELETE` method).
- A "New Branch" link pointing to `/admin/branches/new`.
- The `published` branch is listed but marked as a system branch — it is not intended for direct editing.

### Create Branch

- Page heading: "New Branch".
- Form fields:
  - **Name** — text input, required. Validated per VERS-01 branch validation rules (lowercase alphanumeric with hyphens, max 50 characters, unique).
- Submit button with the text "Create Branch".
- Cancel link with the text "Cancel" pointing to `/admin/branches`.

On valid submission:

- Create the branch.
- Redirect to `/admin/branches` with flash notice: "Branch was successfully created."

On invalid submission:

- Re-render the form with the previously entered name preserved.
- Display validation error messages.
- HTTP status 422.

### Delete Branch

- `DELETE /admin/branches/:id` deletes a branch and **all versions on that branch**.
- Before submitting, the browser displays a confirmation dialog: "Are you sure you want to delete this branch? All versions on this branch will be permanently deleted."
- Protected branches (`main`, `published`) cannot be deleted. Attempting to delete a protected branch returns HTTP 422 with flash alert: "Cannot delete a protected branch."
- On success:
  - Delete all versions belonging to this branch, then delete the branch.
  - If the user's session had this branch selected, reset to `main`.
  - Redirect to `/admin/branches` with flash notice: "Branch was successfully deleted."
- On failure (not found): HTTP 404.
- On failure (non-integer `:id`): HTTP 404.

### Content Operations — Branch-Aware Updates

The following updates apply to the content workflows defined in VERS-02 and VERS-03. Where those tickets specified `main`, the selected branch from the session is now used instead.

#### Index Page

`GET /admin/content` displays all nodes regardless of which branch is selected.

- **Title** — from the current version on the selected branch. If the node has no version on the selected branch, fall back to the current version on `main`. If neither exists, display "(no title)".
- **Status** column — reflects the state on the selected branch:
  - "Draft" — uncommitted version exists on the selected branch.
  - "Committed" — only committed versions on the selected branch.
  - "Not on branch" — no version exists on the selected branch (content shown is from `main`).
- Nodes are ordered by `nodes.updated_at DESC` (unchanged).

#### Show Page

`GET /admin/content/:id` displays content from the current version on the selected branch.

- If the node has a version on the selected branch, display it (same as VERS-02).
- If the node has no version on the selected branch, display the content from `main` with a notice: "This node has not been modified on branch {branch_name}. Editing will create a version on this branch."
- Version status, commit form, and publish controls behave relative to the selected branch (not hardcoded to `main`).

#### Edit / Save Draft

`GET /admin/content/:id/edit` loads content from the current version on the selected branch, falling back to `main` if no version exists on the selected branch.

`PATCH/PUT /admin/content/:id` — when saving on a branch where no version of this node exists:

1. Find the latest committed version of this node on `main` (the fallback source).
2. Create a new uncommitted version on the selected branch with:
   - `title` and `body` — from the submitted form values.
   - `parent_version_id` — null (first version on this branch).
   - `source_version_id` — the latest committed version on `main` that the content was forked from.
3. If an uncommitted version already exists on the selected branch, update it as before (VERS-02 behaviour, unchanged).

#### Commit

`POST /admin/content/:id/commit` commits the uncommitted version on the selected branch (not hardcoded to `main`).

#### Publish

`POST /admin/content/:id/publish` publishes the latest committed version on the **selected branch** to the `published` branch.

- The commit message on the published version becomes `"Publish from {branch_name}"` where `{branch_name}` is the selected branch's name.
- All validation from VERS-03 applies: the version must be committed, must not be on the `published` branch, etc.
- The publish button on the show page is available when the latest committed version on the selected branch is not the source of the current published version.

#### Creating Nodes on Non-Main Branches

When creating a new node while on a branch other than `main`:

- The node is created normally (slug on node).
- The initial uncommitted version is created on the **selected branch** (not `main`).
- This means the node initially exists only on the selected branch. It has no version on `main` until content is explicitly merged or created there.

### The `published` Branch in the Selector

The `published` branch appears in the branch selector but operates in **read-only mode** when selected:

- The index page shows published content (latest versions on the `published` branch).
- The show page shows published content.
- The "Edit Node", "Commit", and "Publish" actions are **not available** when the `published` branch is selected. The edit link, commit form, and publish button are hidden.
- A notice is displayed on the show page: "The published branch is read-only. Switch to another branch to edit."

## Acceptance Criteria

### Branch Selector

- [ ] The admin layout displays the currently selected branch name.
- [ ] The branch selector lists all branches, with `main` first.
- [ ] Switching branches stores the selection in the session and redirects back.
- [ ] On first visit (no session), the selected branch defaults to `main`.
- [ ] If the session references a deleted branch, it falls back to `main`.

### Branch List

- [ ] `GET /admin/branches` returns HTTP 200 and lists all branches.
- [ ] Protected branches are marked as "Yes" in the Protected column.
- [ ] Non-protected branches have a "Delete" button.
- [ ] A "New Branch" link is present.

### Create Branch

- [ ] `GET /admin/branches/new` returns HTTP 200 and displays the new-branch form.
- [ ] Creating a branch with a valid name succeeds and redirects with flash "Branch was successfully created."
- [ ] Creating a branch with a blank name fails with a validation error.
- [ ] Creating a branch with an invalid format fails with a validation error.
- [ ] Creating a branch with a duplicate name (case-insensitive) fails with a validation error.
- [ ] Creating a branch with a name longer than 50 characters fails with a validation error.
- [ ] On validation failure, previously entered values are preserved.
- [ ] On validation failure, the response status is 422.

### Delete Branch

- [ ] Deleting a non-protected branch succeeds and redirects with flash "Branch was successfully deleted."
- [ ] All versions on the deleted branch are removed.
- [ ] Deleting a protected branch returns 422 with alert "Cannot delete a protected branch."
- [ ] If the deleted branch was the selected branch, the session resets to `main`.
- [ ] A confirmation dialog is shown before deletion.
- [ ] `DELETE /admin/branches/999` returns HTTP 404.
- [ ] `DELETE /admin/branches/abc` returns HTTP 404.

### Content — Branch Awareness

- [ ] The index page shows titles from the current version on the selected branch, falling back to `main`.
- [ ] The index page shows "Not on branch" for nodes without versions on the selected branch.
- [ ] The show page displays content from the selected branch, falling back to `main`.
- [ ] When falling back to `main`, a notice explains the node hasn't been modified on this branch.
- [ ] Editing and saving on a branch where the node has no version creates a new version on that branch with `source_version_id` pointing to the `main` version.
- [ ] Committing operates on the selected branch.
- [ ] Publishing operates on the selected branch, with the commit message reflecting the branch name.
- [ ] Creating a node while on a non-main branch creates the initial version on the selected branch.

### Published Branch — Read-Only

- [ ] When the `published` branch is selected, the index page shows published content.
- [ ] When the `published` branch is selected, the show page shows published content.
- [ ] The edit link is not displayed when the `published` branch is selected.
- [ ] The commit form is not displayed when the `published` branch is selected.
- [ ] The publish button is not displayed when the `published` branch is selected.
- [ ] A read-only notice is displayed on the show page.

## Security Considerations

- **Session integrity:** The `current_branch_id` stored in the session must be validated on every request — confirm the branch exists before using it. If the branch has been deleted, fall back to `main`.
- **CSRF protection:** The switch-branch form, create form, and delete form must include CSRF tokens.
- **Protected branch enforcement:** Branch deletion restrictions must be enforced at the model level (per VERS-01), not only at the controller level.
- **Authorisation boundary:** The `published` branch's read-only restriction is enforced at the controller/view level. The model-level restrictions from VERS-01 (no uncommitted versions on `published`) provide a backstop.
- **Branch name validation:** Branch names are user input and must be validated strictly. The format restriction (lowercase alphanumeric + hyphens) prevents injection in URLs and templates.

## Accessibility Considerations

- The branch selector in the admin layout is keyboard-accessible and navigable with screen readers.
- The currently selected branch is announced clearly — not just indicated by visual styling. Use `aria-current="true"` or equivalent on the selected branch option.
- The branch list table uses semantic HTML (`<table>`, `<thead>`, `<th scope="col">`).
- The "Delete" button is inside a `<form>` with a `<button>`, not a styled link.
- The read-only notice on the `published` branch is in a container with `role="status"` so screen readers announce it.
- The "Not on branch" status in the index table is conveyed through text, not colour alone.
- All forms (create branch, delete branch, switch branch) follow the same accessibility patterns as CORE-03 (labels, aria-describedby, aria-invalid, role="alert" on errors).

## Implementation Notes

### Rails

- Generate a `Admin::BranchesController` with `index`, `new`, `create`, and `destroy` actions.
- Add routes:
  ```ruby
  namespace :admin do
    resources :branches, only: [:index, :new, :create, :destroy]
    post 'switch-branch', to: 'branches#switch', as: :switch_branch
  end
  ```
- Implement `switch` action: set `session[:current_branch_id]` and redirect back.
- Add a `current_branch` helper method in `ApplicationController` (or a concern) that reads from the session and falls back to `main`:
  ```ruby
  def current_branch
    @current_branch ||= Branch.find_by(id: session[:current_branch_id]) || Branch.find_by!(name: 'main')
  end
  helper_method :current_branch
  ```
- Update `Admin::ContentController` to use `current_branch` everywhere it previously hardcoded the `main` branch.
- Update the admin layout (`application.html.erb`) to include the branch selector partial.
- For branch deletion, override the `versions.branch_id` FK constraint to allow programmatic deletion: delete versions first within a transaction, then delete the branch. Alternatively, update the FK to `ON DELETE CASCADE` in a migration if preferred.
- The `published` branch read-only check can be a `before_action` on edit/update/commit/publish actions: `redirect_to admin_content_path(@node), alert: "..." if current_branch.name == 'published'`.
- For the index page fallback logic, consider a method on `Node` like `current_version_on(branch, fallback_branch: nil)` that checks the given branch first, then the fallback.

### Rust (Actix)

- Create a `admin::branches` module with handlers for list, new, create, delete, and switch.
- Store `current_branch_id` in the session (using `actix-session`).
- Add a helper or middleware that extracts the current branch from the session on each request, falling back to `main`.
- Update all content handlers to accept the current branch from the session instead of hardcoding `main`.
- For the branch selector, render it in the base admin template using the branch list and current selection.
- Delete branch by deleting versions in a transaction, then the branch row.
- For the `published` branch read-only check, guard the relevant handlers and conditionally render/hide controls in templates.
