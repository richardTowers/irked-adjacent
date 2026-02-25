use actix_web::cookie::Cookie;
use actix_web::http::StatusCode;
use actix_web::{web, HttpRequest, HttpResponse};
use chrono::NaiveDateTime;
use serde_json::json;
use tera::Context;

use crate::models::node::{NewNode, Node};
use crate::AppState;

// ---------------------------------------------------------------------------
// Form data
// ---------------------------------------------------------------------------

/// Form data for node creation. Only these fields are accepted from the form,
/// serving as the Actix equivalent of Rails' strong parameters:
///   `params.require(:node).permit(:title, :slug, :body, :published)`
#[derive(serde::Deserialize)]
pub struct NodeFormData {
    pub title: Option<String>,
    pub slug: Option<String>,
    pub body: Option<String>,
    /// Checkbox value: present as "1" when checked, absent when unchecked.
    pub published: Option<String>,
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Format a NaiveDateTime as "day Month Year HH:MM" (e.g. "25 February 2026 14:30").
/// Matches the Rails strftime("%-d %B %Y %H:%M") format used in the admin views.
fn format_datetime(dt: NaiveDateTime) -> String {
    dt.format("%-d %B %Y %H:%M").to_string()
}

/// Read the flash notice cookie from the request, if present.
fn read_flash(req: &HttpRequest) -> Option<String> {
    req.cookie("flash_notice").map(|c| c.value().to_string())
}

/// Render a Tera template as an HTTP response.
///
/// - Reads any `flash_notice` cookie from the request and makes it available
///   in the template context, then clears the cookie on the response.
/// - Returns the response with the given HTTP status code.
/// - Falls back to a 500 plain-text response if template rendering fails.
fn render_page(
    templates: &tera::Tera,
    name: &str,
    ctx: &mut Context,
    req: &HttpRequest,
    status: StatusCode,
) -> HttpResponse {
    let flash = read_flash(req);
    if let Some(ref notice) = flash {
        ctx.insert("flash_notice", notice);
    }

    match templates.render(name, ctx) {
        Ok(body) => {
            let mut builder = HttpResponse::build(status);
            builder.content_type("text/html; charset=utf-8");
            // Clear the flash cookie after reading so it only shows once
            if flash.is_some() {
                builder.cookie(
                    Cookie::build("flash_notice", "")
                        .path("/")
                        .max_age(actix_web::cookie::time::Duration::seconds(0))
                        .finish(),
                );
            }
            builder.body(body)
        }
        Err(e) => {
            log::error!("Template render error: {e}");
            HttpResponse::InternalServerError()
                .content_type("text/plain")
                .body("Template rendering failed")
        }
    }
}

// ---------------------------------------------------------------------------
// Health check
// ---------------------------------------------------------------------------

/// Health check endpoint — equivalent to Rails' /up
pub async fn health_check(data: web::Data<AppState>) -> HttpResponse {
    match sqlx::query("SELECT 1").execute(&data.db).await {
        Ok(_) => HttpResponse::Ok()
            .content_type("text/html; charset=utf-8")
            .body("<html><body style=\"background-color: green\"></body></html>"),
        Err(_) => HttpResponse::InternalServerError()
            .content_type("text/plain")
            .body("Database connection failed"),
    }
}

// ---------------------------------------------------------------------------
// Root redirect
// ---------------------------------------------------------------------------

/// Redirect / to /admin/content, matching Rails' `root to: redirect("/admin/content")`.
pub async fn root_redirect() -> HttpResponse {
    HttpResponse::Found()
        .insert_header(("Location", "/admin/content"))
        .finish()
}

// ---------------------------------------------------------------------------
// Admin content
// ---------------------------------------------------------------------------

/// GET /admin/content — List all nodes, ordered by updated_at descending.
///
/// Equivalent to Rails' Admin::ContentController#index.
/// Shows a table of nodes or an empty-state message when there are none.
pub async fn admin_content_index(
    data: web::Data<AppState>,
    req: HttpRequest,
) -> HttpResponse {
    let nodes = match Node::all_ordered(&data.db).await {
        Ok(nodes) => nodes,
        Err(_) => {
            return HttpResponse::InternalServerError()
                .content_type("text/plain")
                .body("Failed to load content");
        }
    };

    // Build view data with pre-formatted dates for the template.
    // In Rails this happens implicitly via strftime in ERB; in Rust we prepare
    // the data before handing it to the template engine.
    let node_views: Vec<serde_json::Value> = nodes
        .iter()
        .map(|n| {
            json!({
                "id": n.id,
                "title": &n.title,
                "slug": &n.slug,
                "published": n.published,
                "updated_at": format_datetime(n.updated_at),
            })
        })
        .collect();

    let mut ctx = Context::new();
    ctx.insert("nodes", &node_views);

    render_page(
        &data.templates,
        "admin/content/index.html",
        &mut ctx,
        &req,
        StatusCode::OK,
    )
}

/// GET /admin/content/{id} — Show a single node's details.
///
/// Equivalent to Rails' Admin::ContentController#show.
/// Returns 404 for non-existent nodes. The path parameter is accepted as a
/// String and parsed manually so that non-integer IDs (e.g. "/admin/content/abc")
/// also return 404 — matching the Rails route constraint `{ id: /\d+/ }`.
pub async fn admin_content_show(
    data: web::Data<AppState>,
    path: web::Path<String>,
    req: HttpRequest,
) -> HttpResponse {
    // Parse the ID as an integer — non-numeric IDs get 404, matching Rails'
    // route constraint: constraints: { id: /\d+/ }
    let id: i64 = match path.into_inner().parse() {
        Ok(id) => id,
        Err(_) => {
            return HttpResponse::NotFound()
                .content_type("text/plain")
                .body("Not Found");
        }
    };

    let node = match Node::find(&data.db, id).await {
        Ok(Some(node)) => node,
        Ok(None) => {
            return HttpResponse::NotFound()
                .content_type("text/plain")
                .body("Not Found");
        }
        Err(_) => {
            return HttpResponse::InternalServerError()
                .content_type("text/plain")
                .body("Database error");
        }
    };

    let node_view = json!({
        "id": node.id,
        "title": &node.title,
        "slug": &node.slug,
        "body": node.body.as_deref().unwrap_or(""),
        "published": node.published,
        "published_at": node.published_at
            .map(format_datetime)
            .unwrap_or_else(|| "\u{2014}".to_string()),
        "created_at": format_datetime(node.created_at),
        "updated_at": format_datetime(node.updated_at),
    });

    let mut ctx = Context::new();
    ctx.insert("node", &node_view);

    render_page(
        &data.templates,
        "admin/content/show.html",
        &mut ctx,
        &req,
        StatusCode::OK,
    )
}

/// GET /admin/content/new — Display the new node form.
///
/// Equivalent to Rails' Admin::ContentController#new.
/// Renders an empty form with no validation errors.
pub async fn admin_content_new(
    data: web::Data<AppState>,
    req: HttpRequest,
) -> HttpResponse {
    let mut ctx = Context::new();
    ctx.insert(
        "node",
        &json!({
            "title": "",
            "slug": "",
            "body": "",
            "published": false,
        }),
    );
    ctx.insert("errors", &json!({"title": [], "slug": []}));
    ctx.insert("error_messages", &Vec::<String>::new());

    render_page(
        &data.templates,
        "admin/content/new.html",
        &mut ctx,
        &req,
        StatusCode::OK,
    )
}

/// POST /admin/content — Create a new node.
///
/// Equivalent to Rails' Admin::ContentController#create.
/// On success: redirects to the show page with a flash notice (303 See Other).
/// On failure: re-renders the form with validation errors and HTTP 422.
pub async fn admin_content_create(
    data: web::Data<AppState>,
    req: HttpRequest,
    form: web::Form<NodeFormData>,
) -> HttpResponse {
    let title = form.title.clone().unwrap_or_default();
    let slug = form.slug.clone().filter(|s| !s.is_empty());
    let body = form.body.clone().filter(|s| !s.is_empty());
    // HTML checkboxes send their value ("1") when checked and nothing when
    // unchecked. This is different from Rails' hidden-field trick, but achieves
    // the same result with our Option<String> deserialization.
    let published = form.published.as_deref() == Some("1");

    let params = NewNode {
        title: title.clone(),
        slug: slug.clone(),
        body: body.clone(),
        published,
    };

    match Node::create(&data.db, params).await {
        Ok(node) => {
            // Redirect to the show page with a flash notice stored in a cookie.
            // Uses 303 See Other — the correct status for POST-redirect-GET.
            HttpResponse::SeeOther()
                .cookie(
                    Cookie::build("flash_notice", "Node was successfully created.")
                        .path("/")
                        .http_only(true)
                        .finish(),
                )
                .insert_header(("Location", format!("/admin/content/{}", node.id)))
                .finish()
        }
        Err(errors) => {
            // Re-render the form preserving the submitted values and showing
            // validation errors, returning 422 Unprocessable Entity.
            let empty_vec = vec![];
            let error_messages = errors.full_messages();
            let title_errors = errors.get("title").unwrap_or(&empty_vec);
            let slug_errors = errors.get("slug").unwrap_or(&empty_vec);

            let mut ctx = Context::new();
            ctx.insert(
                "node",
                &json!({
                    "title": &title,
                    "slug": slug.as_deref().unwrap_or(""),
                    "body": body.as_deref().unwrap_or(""),
                    "published": published,
                }),
            );
            ctx.insert(
                "errors",
                &json!({
                    "title": title_errors,
                    "slug": slug_errors,
                }),
            );
            ctx.insert("error_messages", &error_messages);

            render_page(
                &data.templates,
                "admin/content/new.html",
                &mut ctx,
                &req,
                StatusCode::UNPROCESSABLE_ENTITY,
            )
        }
    }
}
