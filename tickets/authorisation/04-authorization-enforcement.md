# AUTH-04: Authorization Enforcement

## Summary

Enforce authorization on node CRUD operations. Only members of a node's team can view, edit, or delete it in the admin interface. Creating a node requires specifying a team (from the teams the user belongs to). This ticket modifies the existing content controllers and views to integrate team-based access control.

## Dependencies

- **AUTH-01** — Team and Membership models.
- **AUTH-02** — Node team ownership.
- **AUTH-03** — Team management UI (users need to be in teams first).
- **CORE-02 through CORE-05** — Existing node CRUD functionality.

## Requirements

### Authorization Rules

| Action        | Rule                                                             |
|---------------|------------------------------------------------------------------|
| List nodes    | Show only nodes belonging to teams the current user is a member of. |
| View node     | User must be a member of the node's team.                        |
| Create node   | User must be a member of the team they are creating the node in. |
| Edit node     | User must be a member of the node's team.                        |
| Delete node   | User must be a member of the node's team.                        |

### Node Listing Changes (`GET /admin/content`)

- The index page must only show nodes belonging to the current user's teams.
- Nodes with no team (legacy unassigned nodes) are not shown to anyone.
- The table should include a "Team" column showing the team name.

### Node Creation Changes (`GET /admin/content/new`, `POST /admin/content`)

- The new-node form must include a **team selector** — a dropdown (`<select>`) listing the teams the current user belongs to.
  - If the user belongs to exactly one team, pre-select it (but still show the dropdown for clarity).
  - If the user belongs to no teams, display a message instead of the form: "You need to be a member of a team before you can create content." with a link to create a team.
- The selected `team_id` must be included in the form submission.
- On the server, validate that the submitted `team_id` belongs to one of the current user's teams. If not, reject with 422 and an error.

### Node View/Edit/Delete Changes

- When loading a node for show, edit, update, or destroy: scope the query to the current user's teams. If the node doesn't belong to one of their teams (or doesn't exist), return 404.
- The show and edit pages should display the team name somewhere visible (e.g. near the title or in a metadata section).
- The edit form should **not** include a team selector — a node's team cannot be changed through the normal edit flow (reassignment is a deliberate admin action, not a casual edit). This can be added later.

### Unauthorized Access Behaviour

- **Not a member of the node's team:** 404 (do not reveal the node exists).
- **Not authenticated:** redirect to login (existing behaviour).
- **No teams at all:** can access `/admin/content` but sees an empty list and a prompt to join or create a team.

### Public View (if applicable)

- Published nodes should remain visible to unauthenticated users on the public site (if a public-facing view exists) regardless of team ownership. Authorization only applies to admin actions.

## Acceptance Criteria

- [ ] `GET /admin/content` lists only nodes belonging to the current user's teams.
- [ ] `GET /admin/content` includes a "Team" column.
- [ ] A user with no teams sees an empty listing with guidance to create or join a team.
- [ ] `GET /admin/content/new` shows a team selector dropdown populated with the user's teams.
- [ ] Creating a node with a valid team succeeds.
- [ ] Creating a node with a team the user is not a member of fails with 422.
- [ ] `GET /admin/content/:id` returns 404 for a node belonging to another team.
- [ ] `GET /admin/content/:id/edit` returns 404 for a node belonging to another team.
- [ ] `PATCH /admin/content/:id` returns 404 for a node belonging to another team.
- [ ] `DELETE /admin/content/:id` returns 404 for a node belonging to another team.
- [ ] The show page displays the node's team name.
- [ ] The edit form does not allow changing the node's team.
- [ ] Nodes with no team (null `team_id`) are not visible in the admin listing.
- [ ] `team_id` is included in permitted parameters for node creation.
- [ ] Existing acceptance tests for node CRUD are updated to account for team membership (test users must be in a team, and nodes must belong to that team).

## Security Considerations

- **Scope all queries:** Never load a node by ID alone in the admin context. Always scope through the current user's teams. This is the primary defense — if the query is scoped correctly, authorization is enforced by default.
- **Validate team_id on creation:** The `team_id` from the form must be checked against the user's actual memberships, not just validated as a valid team. A user should not be able to create content in a team they don't belong to by crafting a request.
- **404 vs 403:** Return 404 for unauthorized access to avoid revealing resource existence.
- **IDOR prevention:** The scoped query approach prevents insecure direct object reference by construction — you can't reference an object you can't query.

## Accessibility Considerations

- The team selector (`<select>`) must have a `<label>` with text "Team" and a matching `for` attribute.
- If the team selector has a validation error, it follows the same `aria-describedby` / `aria-invalid` pattern as other fields.
- The "no teams" empty state message should be a paragraph, not just a flash — it's structural, not transient.
- The team name on show/edit pages should be in a clearly labelled section (e.g. within a definition list or a labelled `<span>`).

## Implementation Notes

### Rails

- Add an `Authorization` concern (or extend the existing `Authentication` concern) that provides a helper like `user_teams` and `authorized_nodes`.
- In `Admin::ContentController`, replace `Node.all` / `Node.find(params[:id])` with scoped queries:
  ```ruby
  # Index
  Node.where(team: Current.user.teams).order(updated_at: :desc)

  # Find for show/edit/update/destroy
  Node.where(team: Current.user.teams).find(params[:id])
  ```
- Add `team_id` to strong parameters for create: `params.require(:node).permit(:title, :slug, :body, :published, :team_id)`.
- Add a validation in the create action (or a custom validator) that checks `Current.user.teams.exists?(id: node_params[:team_id])`.
- Update the form partial to include the team selector (only on new, not edit).
- Update existing tests to set up team membership before testing node operations.

### Rust (Actix)

- Scope all node queries through the user's team memberships using a JOIN or subquery.
- Add the team selector to the creation form template.
- Validate team membership in the creation handler.
- Return 404 for unauthorized node access.
