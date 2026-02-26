# VERS-03: Publishing Workflow

## Summary

Add the ability to publish committed versions of nodes. Publishing creates a merge-commit on the `published` branch (per VERS-01), making the content available for public display. This ticket covers the admin-side publish action, published status display, and a basic public route for viewing published content. All publishing in this ticket originates from the `main` branch — publishing from other branches is introduced with branch management (VERS-04).

## Dependencies

- **VERS-01** — Branch and version schema (publish operation defined at the model level).
- **VERS-02** — Commit workflow (nodes must be committed before they can be published).

## Requirements

### Routes

| Method | Path                         | Action     | Notes                          |
|--------|------------------------------|------------|--------------------------------|
| POST   | /admin/content/:id/publish   | Publish    | **New** — admin action         |
| GET    | /:slug                       | Public Show | **New** — public-facing route  |

### Show Page Updates

The show page (from VERS-02) gains a published status section and publish controls.

#### Published Status Display

Below the existing version status ("Draft" / "Committed"), display the published status:

- **"Not published"** — the node has no version on the `published` branch.
- **"Published"** — the node has a version on the `published` branch, and the source of the latest published version is the latest committed version on `main`. Display the `committed_at` timestamp of the published version.
- **"Published (updates pending)"** — the node has a version on the `published` branch, but the latest committed version on `main` is newer than the source of the latest published version. Display the `committed_at` timestamp of the published version.

#### Publish Button

Display a publish form on the show page when **all** of the following are true:

1. The node has at least one committed version on `main`.
2. The latest committed version on `main` is **not** the source of the current published version (i.e. there is something new to publish — either the node has never been published, or newer commits exist).
3. There is **no** uncommitted version on `main` for this node. If there is an uncommitted draft, display the message "Commit your draft before publishing" instead of the publish button.

The publish form contains:

- A submit button with the text "Publish".
- The form submits `POST` to `/admin/content/:id/publish`.
- No additional fields — the system automatically publishes the latest committed version on `main`.

When the published version is already up-to-date (latest committed on `main` is the source of the current published version), display no publish button — the "Published" status is sufficient.

### Index Page Updates

Add a **Published** column to the nodes table (from VERS-02):

- **"Yes"** — the node has at least one version on the `published` branch.
- **"No"** — the node has no version on the `published` branch.

### Publish Action

`POST /admin/content/:id/publish` publishes the latest committed version on `main` for the given node.

The operation:

1. Find the node by `:id`. Return 404 if not found.
2. Find the latest committed version of this node on `main`. If none exists, fail.
3. Execute the publish operation from VERS-01 (create a merge-commit on the `published` branch with the committed version as the source).
4. On success, redirect to the show page (`/admin/content/:id`) with flash notice: "Node was successfully published."

Failure cases:

- **Node not found:** Return HTTP 404.
- **Non-integer `:id`:** Return HTTP 404.
- **No committed version on `main`:** Redirect to show page with flash alert: "No committed version to publish."
- **Already up-to-date:** Redirect to show page with flash alert: "Published version is already up to date." (This guards against double-submit.)

### Public Show Route

`GET /:slug` displays the published version of a node to the public.

- Look up the node by `slug`.
- Find the latest committed version on the `published` branch for that node.
- If the node exists and has a published version, render the public show page with HTTP 200.
- If the node does not exist, or exists but has no version on the `published` branch, return HTTP 404.

#### Public Show Page

A minimal public page displaying:

- **Title** — from the published version, rendered as an `<h1>`.
- **Body** — from the published version, rendered as the page content.

The public page must **not** display:

- Admin controls (edit, delete, publish buttons).
- Version metadata (commit messages, timestamps, branch information).
- Slug (it is in the URL already).

The public page uses a separate layout from the admin interface — or at minimum, does not include admin navigation or styling. Keep the public layout minimal for now; theming is a separate concern.

### Route Priority

The `/:slug` route is a catch-all and must be defined **after** all other routes to avoid intercepting admin or other paths. The route must not match paths that start with `/admin`.

## Acceptance Criteria

### Publish Action

- [ ] `POST /admin/content/:id/publish` publishes the latest committed version on `main` to the `published` branch.
- [ ] After publishing, redirect to the show page with flash "Node was successfully published."
- [ ] The published version's `source_version_id` points to the committed version on `main` that was published.
- [ ] The published version's `parent_version_id` points to the previous published version (or null for first publication).
- [ ] The published version's `commit_message` is "Publish from main".
- [ ] Publishing when no committed version exists redirects with alert "No committed version to publish."
- [ ] Publishing when already up-to-date redirects with alert "Published version is already up to date."
- [ ] `POST /admin/content/999/publish` returns HTTP 404.
- [ ] `POST /admin/content/abc/publish` returns HTTP 404.

### Show Page — Published Status

- [ ] When the node is not published, the status reads "Not published".
- [ ] When the node is published and up-to-date, the status reads "Published" with timestamp.
- [ ] When the node is published but has newer commits on `main`, the status reads "Published (updates pending)".
- [ ] When there are newer commits and no uncommitted draft, the publish button is displayed.
- [ ] When there are newer commits but an uncommitted draft exists, the message "Commit your draft before publishing" is displayed instead of the publish button.
- [ ] When the published version is up-to-date, no publish button is displayed.
- [ ] When the node has never been published and has a committed version, the publish button is displayed.
- [ ] When the node has never been published and only has an uncommitted draft, the "Commit your draft before publishing" message is displayed.

### Index Page

- [ ] The index table has a "Published" column.
- [ ] Nodes with a version on the `published` branch display "Yes".
- [ ] Nodes without a version on the `published` branch display "No".

### Public Show

- [ ] `GET /:slug` for a published node returns HTTP 200 and displays the title and body.
- [ ] `GET /:slug` for an unpublished node returns HTTP 404.
- [ ] `GET /:slug` for a non-existent slug returns HTTP 404.
- [ ] The public page does not display admin controls or version metadata.
- [ ] The title is rendered in an `<h1>` element.
- [ ] The public page uses a layout distinct from the admin interface.

### Route Priority

- [ ] `GET /admin/content` is not intercepted by the `/:slug` route.
- [ ] `GET /admin/content/new` is not intercepted by the `/:slug` route.

## Security Considerations

- **CSRF protection:** The publish form must include a CSRF token. The publish action must verify it.
- **No direct parameter injection:** The publish action does not accept any content parameters — it always publishes the latest committed version on `main`. This prevents an attacker from submitting arbitrary content through the publish endpoint.
- **Public route input validation:** The `:slug` parameter in the public route must be treated as untrusted input. Use parameterised queries — never interpolate the slug directly into SQL.
- **XSS prevention:** All content rendered on the public page (title, body) must be HTML-escaped. If rich text / HTML body content is supported in the future, this must be sanitised — but for now, plain-text escaping is sufficient.
- **Information disclosure:** The public 404 page must not reveal whether a node exists but is unpublished vs. does not exist at all. Both cases must return an identical 404 response.

## Accessibility Considerations

- The "Publish" button is a `<button>` inside a `<form>`, not a styled link. This ensures correct semantics for assistive technology.
- The published status text ("Published", "Not published", "Published (updates pending)") uses semantic markup and does not rely on colour alone to convey meaning.
- The "Commit your draft before publishing" hint message is associated with the publish area and visible to screen readers.
- Flash messages after publishing follow the same accessibility patterns as other flash messages: `role="status"` for notices, `role="alert"` for errors.
- The public show page:
  - Has a meaningful `<title>` element (the node's title).
  - Uses a single `<h1>` for the node title.
  - Has a `<main>` element wrapping the content.
  - Has a `lang` attribute on the `<html>` element.

## Implementation Notes

### Rails

- Add route: `post '/admin/content/:id/publish', to: 'admin/content#publish', as: :publish_admin_content`.
- Add public route: `get '/:slug', to: 'public/content#show', as: :public_content` — defined **last** in `routes.rb` to avoid precedence issues. Consider using a constraint to restrict the slug format (e.g. `constraints: { slug: /[a-z0-9]+(-[a-z0-9]+)*/ }`).
- Add `publish` action to `Admin::ContentController`:
  - Load the node.
  - Find the latest committed version on `main`: `node.versions.committed.where(branch: main_branch).order(committed_at: :desc).first`.
  - Check if already up-to-date by comparing with the latest published version's `source_version_id`.
  - Call the publish operation from VERS-01.
- Create `Public::ContentController` (or `PagesController`) with a `show` action:
  - `Node.find_by!(slug: params[:slug])` — raises `RecordNotFound` (404) if not found.
  - `Version.current_for(node, published_branch)` — if nil, raise `RecordNotFound`.
  - Render with a public layout (`layouts/public` or similar).
- Update `show.html.erb` to include the published status section and conditional publish form.
- Update `index.html.erb` to include the "Published" column.
- Helper methods to determine published state may be useful on the Node model:
  - `node.published?` — has any version on the `published` branch.
  - `node.published_version` — latest committed version on `published`.
  - `node.publish_pending?` — latest committed on `main` is not the source of the latest published.

### Rust (Actix)

- Add route: `web::resource("/admin/content/{id}/publish").route(web::post().to(publish_node))`.
- Add public route: `web::resource("/{slug}").route(web::get().to(public_show))` — registered **last** in the app configuration.
- Implement `publish_node` handler:
  - Load node, find latest committed version on `main`, call `Version::publish()`.
  - Handle all failure cases with appropriate flash messages and redirects.
- Implement `public_show` handler:
  - Look up node by slug, find published version, return 404 if either is missing.
  - Render with a separate public template/layout.
- Add slug format constraint on the public route if Actix supports route guards or path constraints, to avoid matching admin paths.
- Create a minimal public template (`public/show.html`) with its own base layout.
