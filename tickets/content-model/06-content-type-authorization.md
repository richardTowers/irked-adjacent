# CM-06: Content Type Authorization (Editor Role)

## Summary

Add an `editor` role to team memberships and restrict content type management to users with this role. Regular team members can create and edit nodes using existing content types but cannot create, modify, or delete content types themselves. This separates content creation from schema management.

## Dependencies

- **CM-03** — Content type management UI must exist (this ticket adds authorization on top of it).
- **AUTH-01** — Membership model with role column.

## Requirements

### New Membership Role

Add `editor` to the allowed membership roles. The full role list becomes: `member`, `editor`.

A user's role is per-team — a user can be a `member` in one team and an `editor` in another.

### Authorization Matrix

| Action                              | `member` | `editor` |
|-------------------------------------|----------|----------|
| Create nodes                        | Yes      | Yes      |
| Edit/delete own team's nodes        | Yes      | Yes      |
| View content types                  | Yes      | Yes      |
| Create content types                | No       | Yes      |
| Edit content types                  | No       | Yes      |
| Delete content types                | No       | Yes      |
| Add/edit/remove field definitions   | No       | Yes      |

### Enforcement Behaviour

- When a user with the `member` role attempts to access a content type management action (create, edit, delete content type or manage fields), the server returns **403 Forbidden** — not 404.
- Rationale: members can see that content types exist (they use them to create content), so pretending they don't exist (404) would be misleading. 403 accurately communicates "you don't have permission."
- Display a clear error page or message for 403 responses.

### UI Changes

- Hide content type management links (new, edit, delete, field management) from users who do not have the `editor` role in the content type's team.
- The content type list page remains visible to all team members (they need to see what content types are available).
- The content type show page remains visible to all team members (they need to see what fields a content type has). But management controls (edit, delete, add/edit/remove fields) are hidden for non-editors.

### Team Management UI Updates

- The team management UI (AUTH-03) should allow setting a user's role when adding them to a team or editing their membership.
- The role selector should display the available roles with descriptions:
  - **Member** — Can create and manage content.
  - **Editor** — Can create and manage content, and configure content types.

## Acceptance Criteria

- [ ] The `editor` role is a valid membership role.
- [ ] A user can have the `editor` role in one team and `member` in another.
- [ ] An `editor` can create, edit, and delete content types for their team.
- [ ] An `editor` can add, edit, and remove field definitions on their team's content types.
- [ ] A `member` can view content types and their fields.
- [ ] A `member` attempting to create a content type receives a 403 response.
- [ ] A `member` attempting to edit a content type receives a 403 response.
- [ ] A `member` attempting to delete a content type receives a 403 response.
- [ ] A `member` attempting to manage field definitions receives a 403 response.
- [ ] Content type management links are hidden from `member` users in the UI.
- [ ] The content type list and show pages remain accessible to `member` users.
- [ ] A `member` can still create and edit nodes (no regression).
- [ ] The team management UI allows setting a user's role to `member` or `editor`.
- [ ] The 403 error page is accessible and clearly explains the restriction.

## Security Considerations

- Enforce role checks server-side on every mutating request — do not rely on UI-level hiding alone.
- The role check must verify the user's role in the specific team that owns the content type, not just any team.
- Ensure that upgrading a user's role requires appropriate authorization (for now, any team member can manage memberships per AUTH-03 — consider restricting this in a future ticket).

## Accessibility Considerations

- The 403 error page must have a descriptive heading and message.
- The role selector in the team management UI must have an associated `<label>`.
- Role descriptions should be visible (not just tooltip) so all users can understand the difference.
- Hidden management controls should be truly removed from the DOM (not just visually hidden) to avoid confusion for screen reader users.

## Implementation Notes

### Rails

- Update `Membership::ROLES` to `%w[member editor]`.
- Add a helper method on `Membership` or `User`: e.g. `user.editor_for?(team)` that checks if the user has an `editor` membership for the given team.
- Add a `before_action` in `Admin::ContentTypesController` for mutating actions that checks the editor role and renders 403 if not authorized.
- Create a 403 error view (e.g. `app/views/errors/forbidden.html.erb`) or render inline.
- Use conditional rendering in content type views: `<% if current_user.editor_for?(content_type.team) %>`.
- Update the membership form in the team management views to include a role selector.

### Rust (Actix)

- Update the role enum/allowlist to include `editor`.
- Add middleware or extractor that checks the user's role in the relevant team.
- Return 403 status with an error template for unauthorized access.
- Conditionally render management controls in templates based on the user's role.
