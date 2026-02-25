# CORE-02: List and View Nodes

## Summary

Add an admin listing page and a detail (show) page for nodes. These are the first user-facing routes in the CMS and establish the `/admin/content` URL namespace.

## Dependencies

- **CORE-01** — Node model and database schema must exist.

## Requirements

### Routes

| Method | Path                | Action |
|--------|---------------------|--------|
| GET    | /admin/content      | Index  |
| GET    | /admin/content/:id  | Show   |

### Index Page

- Display a table of all nodes ordered by `updated_at` descending (most recently updated first).
- Table columns: **Title**, **Slug**, **Status**, **Updated**.
- The **Title** column contains a link to the node's show page.
- **Status** displays the text "Published" or "Draft" — status must be conveyed through text, not colour alone.
- **Updated** displays the `updated_at` timestamp in a human-readable format.
- When no nodes exist, display the message: "No content yet."
- Include a link to the create-node page (CORE-03) with the text "New Node".
- Page heading: "Content".

### Show Page

- Display the full details of a single node:
  - **Title** (as a page heading)
  - **Slug**
  - **Body** (rendered as plain text — no HTML interpretation)
  - **Status** ("Published" or "Draft")
  - **Published At** (if set; omit or show "—" if nil)
  - **Created At**
  - **Updated At**
- Include a link back to the listing page with the text "Back to content".
- Include a link to the edit page (CORE-04) with the text "Edit".
- If no node exists with the given `:id`, respond with HTTP 404.

### Parameter Validation

- The `:id` parameter must be validated as a positive integer. Non-integer values (e.g. strings, negative numbers) should result in a 404 response, not an unhandled error.

## Acceptance Criteria

- [ ] `GET /admin/content` returns HTTP 200 and displays a table of nodes.
- [ ] Nodes are ordered by `updated_at` descending.
- [ ] Each row shows the node's title, slug, published status (as text), and updated timestamp.
- [ ] Each title links to the node's show page (`/admin/content/:id`).
- [ ] When there are no nodes, the page displays "No content yet."
- [ ] The index page contains a "New Node" link pointing to `/admin/content/new`.
- [ ] `GET /admin/content/:id` returns HTTP 200 and displays the node's full details.
- [ ] The show page displays title, slug, body (as plain text), status, published_at, created_at, and updated_at.
- [ ] Body content is escaped — HTML entities in body text are not rendered as HTML.
- [ ] The show page contains a "Back to content" link pointing to `/admin/content`.
- [ ] The show page contains an "Edit" link pointing to `/admin/content/:id/edit`.
- [ ] `GET /admin/content/999` (non-existent id) returns HTTP 404.
- [ ] `GET /admin/content/abc` (non-integer id) returns HTTP 404.

## Security Considerations

- **Output escaping:** Body content must be escaped before rendering. Never use raw/unescaped HTML output for user-provided content. This prevents stored XSS attacks.
- **Parameter validation:** Reject non-integer `:id` values at the routing or controller level to avoid database errors or injection vectors.

## Accessibility Considerations

- Use semantic HTML: `<table>` with `<thead>`, `<th scope="col">` for column headers.
- Use appropriate heading hierarchy (`<h1>` for page title).
- Status is conveyed via text ("Published"/"Draft"), not via colour or icons alone.
- Links have descriptive text — avoid bare "View" or "Click here". Title text in the table serves as the link to the show page.
- Timestamps should be in a readable format (avoid raw ISO 8601 strings without formatting).

## Implementation Notes

### Rails

- Generate an `Admin::ContentController` (or similar namespaced controller) with `index` and `show` actions.
- Route: `namespace :admin do resources :content, only: [:index, :show] end` — or use explicit route definitions to map `/admin/content` to the controller.
- Use `Node.order(updated_at: :desc)` for the index query.
- Use `find` or `find_by` for the show action; rescue `ActiveRecord::RecordNotFound` to return 404.
- ERB templates with standard Rails escaping (which is on by default).

### Rust (Actix)

- Create handler functions for `list_nodes` and `show_node`.
- Register routes under `/admin/content` in the Actix app configuration.
- Use Tera or Askama templates with auto-escaping enabled.
- Parse `:id` as `i32`/`i64` — Actix path extractors will return 404 for non-integer values automatically.
- Query nodes ordered by `updated_at DESC`.
