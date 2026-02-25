# CORE-05: Delete Nodes

## Summary

Add the ability to permanently delete nodes. This completes the CRUD operations for the Node entity.

## Dependencies

- **CORE-01** — Node model.
- **CORE-02** — Show page (where the delete button lives) and listing page (redirect target after deletion).

## Requirements

### Routes

| Method | Path               | Action  |
|--------|--------------------|---------|
| DELETE | /admin/content/:id | Destroy |

### Delete Mechanism

- The delete action is triggered by a form submission using the `DELETE` HTTP method — **not** a plain link.
- The delete button appears on the node's show page (CORE-02) with the text "Delete Node".
- Before submitting, the browser displays a native confirmation dialog with the message: "Are you sure you want to delete this node? This action cannot be undone."
- The deletion is permanent — there is no soft-delete or trash/recycle bin.

### Success Behaviour

- On successful deletion, redirect to the listing page (`/admin/content`).
- Display a flash message: "Node was successfully deleted."

### Not Found

- If no node exists with the given `:id`, return HTTP 404.

### Parameter Validation

- The `:id` parameter must be validated as a positive integer. Non-integer values should result in a 404 response.

## Acceptance Criteria

- [ ] `DELETE /admin/content/:id` deletes the node and redirects to `/admin/content`.
- [ ] After successful deletion, the flash message "Node was successfully deleted." is displayed.
- [ ] The node no longer appears in the listing after deletion.
- [ ] The delete action is a form submission with `DELETE` method, not a plain link.
- [ ] The delete button on the show page has the text "Delete Node".
- [ ] A browser-native confirmation dialog appears before the form is submitted.
- [ ] The confirmation message reads: "Are you sure you want to delete this node? This action cannot be undone."
- [ ] `DELETE /admin/content/999` (non-existent id) returns HTTP 404.
- [ ] `DELETE /admin/content/abc` (non-integer id) returns HTTP 404.

## Security Considerations

- **CSRF protection:** The delete form must include a CSRF token. The destroy action must verify it.
- **HTTP method:** Deletion must use `DELETE` (or `POST` with a method override) — never `GET`. This prevents accidental deletion via link prefetching or crawlers.
- **No cascade effects yet:** Nodes have no dependent records at this stage, but the delete action should be written to accommodate future cascade/restrict logic.

## Accessibility Considerations

- The delete button must be a `<button>` element inside a `<form>`, not a styled link. This ensures correct semantics for assistive technology.
- The flash message after deletion is announced to screen readers via a container with `role="status"` or `aria-live="polite"`.
- The browser-native confirmation dialog is inherently accessible.

## Implementation Notes

### Rails

- Add a `destroy` action to `Admin::ContentController`.
- Use `button_to` with `method: :delete` and `data: { turbo_confirm: "Are you sure..." }` (Rails 7+/Turbo) or `data: { confirm: "..." }` (Rails UJS) on the show page.
- `find` or `find_by!` for 404 handling.
- Redirect to `admin_content_index_path` with `flash[:notice]`.

### Rust (Actix)

- Add a `delete_node` handler function.
- Render the delete button on the show page as a `<form>` with a hidden `_method` field set to `DELETE` (or handle `DELETE` requests directly).
- Add `onclick="return confirm('...')"` to the submit button for the confirmation dialog.
- Parse `:id` from the path; return 404 if the node is not found.
- Delete the record and redirect to `/admin/content` with a flash message.
