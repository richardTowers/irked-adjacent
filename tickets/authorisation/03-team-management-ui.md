# AUTH-03: Team Management UI

## Summary

Add admin pages for creating teams, viewing team details, and managing team membership. Any authenticated user can create a new team (they become its first member). Any team member can invite other registered users and remove members. This ticket covers the UI and controller actions for team management.

## Dependencies

- **AUTH-01** — Team and Membership models.
- Authentication must be in place.

## Requirements

### Routes

| Method | Path                            | Action              |
|--------|---------------------------------|----------------------|
| GET    | /admin/teams                    | List user's teams    |
| GET    | /admin/teams/new                | New team form        |
| POST   | /admin/teams                    | Create team          |
| GET    | /admin/teams/:id                | Show team + members  |
| GET    | /admin/teams/:id/edit           | Edit team form       |
| PATCH  | /admin/teams/:id                | Update team          |
| DELETE | /admin/teams/:id                | Destroy team         |
| POST   | /admin/teams/:id/members        | Add member           |
| DELETE | /admin/teams/:id/members/:id    | Remove member        |

### Team Listing Page (`GET /admin/teams`)

- Page heading: "Your Teams".
- Displays a table of teams the current user belongs to, ordered by name ascending.
- Columns: Name (linked to show page), Members (count), Nodes (count).
- A "New Team" link/button above the table.
- If the user has no teams, display a message: "You are not a member of any teams yet." with a link to create one.

### New Team Page (`GET /admin/teams/new`)

- Page heading: "New Team".
- Form fields:
  - **Name** — text input, required.
  - **Slug** — text input, optional (auto-generated from name if blank).
- Submit button: "Create Team".
- Cancel link pointing to `/admin/teams`.

### Create Team (`POST /admin/teams`)

- On success: create the team, add the current user as its first member (role: "member"), redirect to the team show page. Flash message: "Team was successfully created."
- On failure: re-render the form with validation errors and HTTP 422.

### Show Team Page (`GET /admin/teams/:id`)

- Page heading: the team name.
- Display team details: name, slug.
- **Members section:**
  - Table of members with columns: Email, Role, Joined (human-readable date), Actions.
  - Each member row has a "Remove" button (except: a member cannot remove themselves if they are the last member — see below).
- **Add member form** (inline on the show page or a separate section):
  - Email address text input.
  - "Add Member" submit button.
  - On success: add the user as a member, redirect back to the show page. Flash: "Member was successfully added."
  - If the email doesn't match any registered user: re-render with error "No user found with that email address."
  - If the user is already a member: re-render with error "That user is already a member of this team."
- **Team actions:**
  - "Edit Team" link.
  - "Delete Team" button (with confirmation dialog).

### Edit Team Page (`GET /admin/teams/:id/edit`)

- Page heading: "Edit Team".
- Same form fields as new, pre-filled with current values.
- Submit button: "Update Team".
- Cancel link pointing to `/admin/teams/:id`.

### Update Team (`PATCH /admin/teams/:id`)

- On success: redirect to team show page. Flash: "Team was successfully updated."
- On failure: re-render form with errors and HTTP 422.

### Destroy Team (`DELETE /admin/teams/:id`)

- Confirmation dialog: "Are you sure you want to delete this team? This action cannot be undone."
- If the team has nodes: do not delete. Redirect back to the team show page with flash error: "Cannot delete a team that still has content. Reassign or delete the team's nodes first."
- On success: redirect to `/admin/teams`. Flash: "Team was successfully deleted."

### Remove Member (`DELETE /admin/teams/:id/members/:id`)

- Confirmation dialog: "Are you sure you want to remove this member?"
- A team must always have at least one member. If this is the last member, reject the removal with flash error: "Cannot remove the last member of a team."
- On success: redirect back to team show page. Flash: "Member was successfully removed."
- A user can remove themselves from a team (unless they're the last member).

### Mass Assignment Protection

- Team: only accept `name` and `slug`.
- Add member: only accept `email_address`.

## Acceptance Criteria

- [ ] `GET /admin/teams` lists only teams the current user belongs to.
- [ ] `GET /admin/teams` shows member and node counts for each team.
- [ ] A user with no teams sees the empty-state message and a link to create a team.
- [ ] `GET /admin/teams/new` displays the new team form.
- [ ] Creating a team with a valid name succeeds and adds the current user as the first member.
- [ ] Creating a team with a blank name fails with a validation error.
- [ ] Leaving the slug blank auto-generates it from the name.
- [ ] `GET /admin/teams/:id` shows team details and member list.
- [ ] Adding a member by email succeeds for a registered user who is not already a member.
- [ ] Adding a member with an unrecognised email shows an error.
- [ ] Adding a member who is already in the team shows an error.
- [ ] Removing a member succeeds and redirects back to the team page.
- [ ] Removing the last member of a team is rejected.
- [ ] Editing a team updates its name and/or slug.
- [ ] Deleting a team with no nodes succeeds.
- [ ] Deleting a team with nodes is rejected with an error message.
- [ ] All team management pages require authentication.
- [ ] A user who is not a member of a team cannot access that team's show/edit pages (returns 404 — do not reveal the team exists).
- [ ] Only `name` and `slug` are accepted for team creation/update.

## Security Considerations

- **Authorization:** All team-specific actions (show, edit, update, destroy, manage members) must verify the current user is a member of the team. Non-members should receive a 404 (not 403) to avoid leaking team existence.
- **CSRF protection:** All mutating actions must verify the CSRF token.
- **Mass assignment:** Whitelist permitted parameters strictly.
- **Member invite by email:** Do not reveal whether an email address is registered or not in a way that enables enumeration. The error "No user found with that email address" is acceptable here because the add-member action is already behind authentication and team membership — the attack surface is limited to authenticated team members.

## Accessibility Considerations

- Every form field has a `<label>` with a matching `for` attribute.
- Required fields have the `required` attribute.
- Validation errors are associated with fields via `aria-describedby`.
- Error summaries have `role="alert"`.
- Flash messages are announced via `role="status"` or `aria-live="polite"`.
- Confirmation dialogs for delete/remove use native browser confirmation.
- Tables use `<th scope="col">` for column headers.
- The "Remove" button for members is distinguishable — consider including the member's email in the button's accessible label (e.g. `aria-label="Remove user@example.com"`).

## Implementation Notes

### Rails

- Create `Admin::TeamsController` with standard CRUD actions.
- Create `Admin::Teams::MembersController` (nested) for add/remove member actions.
- Routes: `namespace :admin do resources :teams do resources :members, only: [:create, :destroy], module: :teams end end`.
- Scope team lookups to current user's teams: `Current.user.teams.find(params[:id])` — this naturally returns 404 for non-members.
- Use `form_with` for all forms.
- The "add member" form can use `User.find_by(email_address: params[:email_address])` to look up the user.

### Rust (Actix)

- Add handlers for each route.
- Scope team queries to the current user's memberships.
- Use templates consistent with the existing admin UI.
- Flash messages via the existing flash mechanism.
