use actix_web::{web, HttpResponse};
use chrono::NaiveDateTime;
use serde_json::json;
use tera::Context;

use crate::models::node::Node;
use crate::AppState;

/// Format a NaiveDateTime as "day Month Year HH:MM" (e.g. "25 February 2026 14:30").
/// Matches the Rails strftime("%-d %B %Y %H:%M") format used in the admin views.
fn format_datetime(dt: NaiveDateTime) -> String {
    dt.format("%-d %B %Y %H:%M").to_string()
}

/// Render a Tera template, returning 500 if rendering fails.
fn render_template(templates: &tera::Tera, name: &str, ctx: &Context) -> HttpResponse {
    match templates.render(name, ctx) {
        Ok(body) => HttpResponse::Ok()
            .content_type("text/html; charset=utf-8")
            .body(body),
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
pub async fn admin_content_index(data: web::Data<AppState>) -> HttpResponse {
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

    render_template(&data.templates, "admin/content/index.html", &ctx)
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

    render_template(&data.templates, "admin/content/show.html", &ctx)
}
