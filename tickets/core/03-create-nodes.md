# CORE-03: Create Nodes

## Summary

Add the ability to create new nodes through an admin form. This introduces the new-node form and the create action, completing the "C" in CRUD.

## Dependencies

- **CORE-01** — Node model and validations.
- **CORE-02** — Listing and show pages (redirect targets after creation).

## Requirements

### Routes

| Method | Path              | Action |
|--------|-------------------|--------|
| GET    | /admin/content/new | New    |
| POST   | /admin/content     | Create |

### Form Page

- Page heading: "New Node".
- Form fields:
  - **Title** — text input, required.
  - **Slug** — text input, optional (auto-generated from title if left blank).
  - **Body** — textarea, optional.
  - **Published** — checkbox, unchecked by default.
- Submit button with the text "Create Node".
- Cancel link with the text "Cancel" pointing to `/admin/content`.

### Success Behaviour

- On valid submission, create the node and redirect to its show page (`/admin/content/:id`).
- Display a flash message: "Node was successfully created."

### Failure Behaviour

- On invalid submission, re-render the form with:
  - All previously entered values preserved in the form fields.
  - Validation error messages displayed.
  - HTTP status 422 (Unprocessable Entity).

### Mass Assignment Protection

- Only accept the following parameters for node creation: `title`, `slug`, `body`, `published`.
- Reject or ignore any other parameters (e.g. `id`, `published_at`, `created_at`).

## Acceptance Criteria

- [ ] `GET /admin/content/new` returns HTTP 200 and displays the new-node form.
- [ ] The form has fields for title, slug, body, and published.
- [ ] Submitting the form with a valid title creates a node and redirects to its show page.
- [ ] After successful creation, the flash message "Node was successfully created." is displayed.
- [ ] Submitting with a blank title re-renders the form with an error message on the title field.
- [ ] On validation failure, previously entered values are preserved in the form.
- [ ] On validation failure, the response status is 422.
- [ ] Leaving the slug blank auto-generates it from the title (per CORE-01 rules).
- [ ] Providing an explicit slug uses that value instead of auto-generating.
- [ ] Submitting with a duplicate slug re-renders the form with an error message on the slug field.
- [ ] Checking the published checkbox sets `published` to true and triggers `published_at` logic (per CORE-01).
- [ ] Only title, slug, body, and published are accepted — other parameters are ignored.
- [ ] The cancel link navigates to `/admin/content`.

## Security Considerations

- **Mass assignment protection:** Whitelist only permitted parameters. Never pass raw request parameters directly to the model.
- **CSRF protection:** The form must include a CSRF token. The create action must verify it.
- **Input validation:** All validation occurs at the model level (CORE-01). The controller must not bypass validation.

## Accessibility Considerations

- Every form field has a `<label>` element with a `for` attribute matching the input's `id`.
- The title field has the `required` attribute set.
- When validation errors occur:
  - Each error message is associated with its field via `aria-describedby`.
  - An error summary appears at the top of the form (or near the submit button) with `role="alert"` so screen readers announce it immediately.
  - Invalid fields have `aria-invalid="true"` set.
- The flash success message after creation is announced to assistive technology (e.g. via a container with `role="status"` or `aria-live="polite"`).

## Implementation Notes

### Rails

- Add `new` and `create` actions to `Admin::ContentController`.
- Use strong parameters: `params.require(:node).permit(:title, :slug, :body, :published)`.
- On failure, `render :new, status: :unprocessable_entity`.
- CSRF token is handled automatically by Rails (`form_with` includes `authenticity_token`).
- Flash messages via `flash[:notice]`.

### Rust (Actix)

- Add handler functions for `new_node` (GET) and `create_node` (POST).
- Deserialize the form body into a struct with only the permitted fields.
- On failure, re-render the template with the submitted values and error messages, returning HTTP 422.
- Implement CSRF protection (e.g. a middleware or per-form token stored in the session).
- Flash messages via `actix-web-flash-messages` or a session-based approach.
