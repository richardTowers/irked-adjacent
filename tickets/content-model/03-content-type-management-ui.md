# CM-03: Content Type Management UI

## Summary

Build the admin interface for creating, viewing, editing, and deleting content types, including managing their field definitions inline. This is the "schema builder" — the UI where users define what kinds of content their team can create and what fields each content type has.

## Dependencies

- **CM-02** — Field definition model must exist.
- **AUTH-04** — Authorization enforcement patterns (team-scoped access).

## Requirements

### Routes

| Method | Path                                      | Action                        |
|--------|-------------------------------------------|-------------------------------|
| GET    | /admin/content-types                      | List all accessible types     |
| GET    | /admin/content-types/new                  | New content type form         |
| POST   | /admin/content-types                      | Create content type           |
| GET    | /admin/content-types/:slug                | Show content type and fields  |
| GET    | /admin/content-types/:slug/edit           | Edit content type form        |
| PATCH  | /admin/content-types/:slug                | Update content type           |
| DELETE | /admin/content-types/:slug                | Delete content type           |
| POST   | /admin/content-types/:slug/fields         | Add field definition          |
| PATCH  | /admin/content-types/:slug/fields/:id     | Update field definition       |
| DELETE | /admin/content-types/:slug/fields/:id     | Remove field definition       |

### Content Type List

- Display all content types belonging to teams the current user is a member of.
- Show name, team, number of fields, and number of nodes for each content type.
- Link each content type to its show page.
- Include a "New content type" link.

### Content Type Form (New/Edit)

- Fields: name, description (optional), team selector (dropdown of user's teams).
- Team selector only shows teams the user belongs to.
- On edit, the team cannot be changed if the content type has nodes.

### Content Type Show Page

- Display content type name, description, team, and slug.
- List all field definitions in position order, showing: name, API key, field type, required status.
- Provide controls to add, edit, reorder, and remove field definitions.
- Show a count of nodes using this content type.
- Show a delete button only when no nodes use this content type.

### Field Definition Management

Field definitions are managed as a nested resource on the content type show page:

- **Add field:** A form (or expandable section) to add a new field with: name, API key, field type (dropdown), required (checkbox), position, and type-specific validations.
- **Edit field:** Inline or modal editing of an existing field's properties. Changing `api_key` or `field_type` on a field that has data in existing nodes should display a warning.
- **Remove field:** Delete a field definition. Display a confirmation warning that existing node data for this field will become orphaned (but not lost — it remains in the JSON).
- **Reorder fields:** The `position` field controls ordering. Provide a way to change position values (number inputs or move-up/move-down buttons).

### Authorization

- Content types are scoped to the user's teams. Users can only see and manage content types belonging to teams they are members of.
- If a user attempts to access a content type belonging to a team they are not in, return 404 (same pattern as AUTH-04 for nodes).
- Note: role-based restrictions (editor vs. member) are added in CM-06. For this ticket, any team member can manage content types.

### Flash Messages

- Display success flash messages after create, update, and delete operations.
- Display error messages when operations fail (e.g. validation errors, delete blocked by existing nodes).

## Acceptance Criteria

- [ ] The content types index page lists all content types for the current user's teams.
- [ ] The new content type form creates a content type with name, description, and team.
- [ ] The team selector only shows teams the user belongs to.
- [ ] Creating a content type with invalid data shows validation errors.
- [ ] The show page displays the content type's details and its field definitions in position order.
- [ ] A field definition can be added to a content type from the show page.
- [ ] A field definition can be edited from the show page.
- [ ] A field definition can be removed from the show page with a confirmation.
- [ ] Field position can be changed to reorder fields.
- [ ] The content type can be edited (name, description).
- [ ] The content type can be deleted when it has no nodes.
- [ ] Deleting a content type that has nodes fails with an error message.
- [ ] Accessing a content type from another team returns 404.
- [ ] Flash messages appear for successful and failed operations.
- [ ] All pages have appropriate page titles.
- [ ] Navigation includes a link to the content types section.

## Security Considerations

- Scope all queries to the current user's teams — never expose content types from other teams.
- Validate team membership server-side on every request, not just in the UI.
- Sanitize all user input (name, description, field names) to prevent XSS.
- Use CSRF protection on all mutating requests.

## Accessibility Considerations

- All form fields must have associated `<label>` elements.
- Validation errors must be linked to their fields using `aria-describedby`.
- Invalid fields must have `aria-invalid="true"`.
- The field list should use semantic markup (e.g. `<table>` or `<dl>`).
- Confirmation dialogs for destructive actions (delete field, delete content type) must be accessible.
- Page titles must be descriptive and unique (e.g. "Edit Blog Post — Content Types").
- Focus management: after adding or removing a field, focus should move to a sensible location.

## Implementation Notes

### Rails

- Generate `Admin::ContentTypesController` and `Admin::FieldDefinitionsController`.
- Use `before_action` to scope content types to the current user's teams (same pattern as `Admin::ContentController` for nodes).
- Content type views go in `app/views/admin/content_types/`.
- Use standard Rails form helpers for the content type form.
- Field definitions can use nested forms or separate controller actions — separate actions (POST/PATCH/DELETE on the fields sub-resource) are simpler and avoid complex `accepts_nested_attributes_for` setups.
- Add a link to content types in the admin navigation.

### Rust (Actix)

- Create handlers for content type CRUD and field definition management.
- Use Tera or similar templates for rendering.
- Scope queries with a join to memberships to enforce team access.
- Field management can be separate handler functions mounted under the content type routes.
