# CORE-04: Edit Nodes

## Summary

Add the ability to edit existing nodes through an admin form. This introduces the edit form and the update action, completing the "U" in CRUD.

## Dependencies

- **CORE-01** — Node model and validations.
- **CORE-02** — Show page (redirect target after update, and source of the "Edit" link).
- **CORE-03** — Create nodes (the form structure and patterns established there are reused here).

## Requirements

### Routes

| Method    | Path                     | Action |
|-----------|--------------------------|--------|
| GET       | /admin/content/:id/edit  | Edit   |
| PATCH/PUT | /admin/content/:id       | Update |

### Form Page

- Page heading: "Edit Node".
- Form fields — same as the create form (CORE-03), pre-filled with the node's current values:
  - **Title** — text input, required, pre-filled.
  - **Slug** — text input, pre-filled.
  - **Body** — textarea, pre-filled.
  - **Published** — checkbox, reflecting the node's current published state.
- Submit button with the text "Update Node".
- Cancel link with the text "Cancel" pointing to the node's show page (`/admin/content/:id`).

### Success Behaviour

- On valid submission, update the node and redirect to its show page (`/admin/content/:id`).
- Display a flash message: "Node was successfully updated."

### Failure Behaviour

- On invalid submission, re-render the form with:
  - The submitted (invalid) values preserved in the form fields.
  - Validation error messages displayed.
  - HTTP status 422 (Unprocessable Entity).

### Not Found

- If no node exists with the given `:id`, both the edit and update actions return HTTP 404.

### Published Timestamp Behaviour

- When the published checkbox is checked (false -> true transition), `published_at` follows the rules defined in CORE-01.
- When the published checkbox is unchecked (true -> false transition), `published_at` is preserved.

### Mass Assignment Protection

- Only accept the following parameters for node update: `title`, `slug`, `body`, `published`.
- Reject or ignore any other parameters.

## Acceptance Criteria

- [ ] `GET /admin/content/:id/edit` returns HTTP 200 and displays the edit form pre-filled with the node's current values.
- [ ] The form has fields for title, slug, body, and published.
- [ ] Submitting the form with valid data updates the node and redirects to its show page.
- [ ] After successful update, the flash message "Node was successfully updated." is displayed.
- [ ] Submitting with a blank title re-renders the form with an error message on the title field.
- [ ] On validation failure, the submitted values are preserved in the form.
- [ ] On validation failure, the response status is 422.
- [ ] Changing the slug to a value that already exists on another node re-renders with an error.
- [ ] Checking the published checkbox (false -> true) sets `published_at` when it was nil.
- [ ] Unchecking the published checkbox (true -> false) preserves `published_at`.
- [ ] Only title, slug, body, and published are accepted — other parameters are ignored.
- [ ] `GET /admin/content/999/edit` (non-existent id) returns HTTP 404.
- [ ] `PATCH /admin/content/999` (non-existent id) returns HTTP 404.
- [ ] The cancel link navigates to `/admin/content/:id`.

## Security Considerations

- **Mass assignment protection:** Same as CORE-03 — whitelist only permitted parameters.
- **CSRF protection:** The form must include a CSRF token. The update action must verify it.
- **Parameter validation:** Validate `:id` as a positive integer (same as CORE-02).

## Accessibility Considerations

- Same form accessibility requirements as CORE-03: labels with `for`/`id`, `required` attribute on title, `aria-describedby` for error messages, `aria-invalid="true"` on invalid fields, error summary with `role="alert"`.
- Flash success message announced via `role="status"` or `aria-live="polite"`.

## Implementation Notes

### Rails

- Add `edit` and `update` actions to `Admin::ContentController`.
- Reuse the form partial from CORE-03 (`_form.html.erb`) for both new and edit views.
- Use strong parameters: `params.require(:node).permit(:title, :slug, :body, :published)`.
- Use `PATCH` as the primary HTTP method (Rails default for updates). `PUT` should also be accepted.
- `find` or `find_by!` raises `ActiveRecord::RecordNotFound` for 404 handling.

### Rust (Actix)

- Add handler functions for `edit_node` (GET) and `update_node` (PATCH/PUT).
- Reuse the form template from CORE-03, passing the existing node's data for pre-filling.
- Parse `:id` from the path and query the database; return 404 if not found.
- Deserialize the form body into the same struct used for creation, with only permitted fields.
