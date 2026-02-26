use actix_web::cookie::Cookie;
use actix_web::http::StatusCode;
use actix_web::{web, HttpRequest, HttpResponse};
use chrono::NaiveDateTime;
use serde_json::json;
use tera::Context;

use crate::models::branch::Branch;
use crate::models::node::{CreateNodeWithVersion, Node};
use crate::models::version::{NewVersion, UpdateVersion, Version};
use crate::AppState;

// ---------------------------------------------------------------------------
// Form data
// ---------------------------------------------------------------------------

/// Form data for node creation (VERS-02: title, slug, body — no published).
/// Mirrors Rails' `params.require(:node).permit(:title, :slug, :body)`.
#[derive(serde::Deserialize)]
pub struct CreateFormData {
    pub title: Option<String>,
    pub slug: Option<String>,
    pub body: Option<String>,
}

/// Form data for committing a version.
#[derive(serde::Deserialize)]
pub struct CommitFormData {
    pub commit_message: Option<String>,
}

/// Form data for method override. HTML forms only support GET and POST, so
/// Rails uses a hidden `_method` field to tunnel DELETE/PATCH/PUT requests
/// through POST. This struct captures that field along with all possible
/// form fields for the various actions routed through POST.
#[derive(serde::Deserialize)]
pub struct MethodOverrideForm {
    #[serde(rename = "_method")]
    pub method: Option<String>,
    // Fields for the update (PATCH) action
    pub title: Option<String>,
    pub body: Option<String>,
    // Fields for the commit action
    pub commit_message: Option<String>,
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
fn read_flash(req: &HttpRequest, name: &str) -> Option<String> {
    req.cookie(name).map(|c| c.value().to_string())
}

/// Build a cookie-clearing cookie (max_age=0) for a given name.
fn clear_cookie(name: &str) -> Cookie<'static> {
    Cookie::build(name.to_string(), "")
        .path("/")
        .max_age(actix_web::cookie::time::Duration::seconds(0))
        .finish()
}

/// Render a Tera template as an HTTP response.
///
/// - Reads flash_notice and flash_alert cookies and makes them available
///   in the template context, then clears both on the response.
/// - Returns the response with the given HTTP status code.
/// - Falls back to a 500 plain-text response if template rendering fails.
fn render_page(
    templates: &tera::Tera,
    name: &str,
    ctx: &mut Context,
    req: &HttpRequest,
    status: StatusCode,
) -> HttpResponse {
    let flash_notice = read_flash(req, "flash_notice");
    let flash_alert = read_flash(req, "flash_alert");

    if let Some(ref notice) = flash_notice {
        ctx.insert("flash_notice", notice);
    }
    if let Some(ref alert) = flash_alert {
        ctx.insert("flash_alert", alert);
    }

    match templates.render(name, ctx) {
        Ok(body) => {
            let mut builder = HttpResponse::build(status);
            builder.content_type("text/html; charset=utf-8");
            if flash_notice.is_some() {
                builder.cookie(clear_cookie("flash_notice"));
            }
            if flash_alert.is_some() {
                builder.cookie(clear_cookie("flash_alert"));
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

/// Build a redirect response with a flash notice cookie.
fn redirect_with_notice(location: &str, message: &str) -> HttpResponse {
    HttpResponse::SeeOther()
        .cookie(
            Cookie::build("flash_notice", message.to_string())
                .path("/")
                .http_only(true)
                .finish(),
        )
        .insert_header(("Location", location.to_string()))
        .finish()
}

/// Build a redirect response with a flash alert cookie.
fn redirect_with_alert(location: &str, message: &str) -> HttpResponse {
    HttpResponse::SeeOther()
        .cookie(
            Cookie::build("flash_alert", message.to_string())
                .path("/")
                .http_only(true)
                .finish(),
        )
        .insert_header(("Location", location.to_string()))
        .finish()
}

/// Parse a path segment as a positive integer ID, returning None for
/// non-integer values (which should result in a 404).
fn parse_id(raw: &str) -> Option<i64> {
    raw.parse::<i64>().ok()
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
// Admin content — Index
// ---------------------------------------------------------------------------

/// GET /admin/content — List all nodes with their current version on main.
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

    let main_branch = match Branch::find_by_name(&data.db, "main").await {
        Ok(Some(b)) => b,
        _ => {
            return HttpResponse::InternalServerError()
                .content_type("text/plain")
                .body("Main branch not found");
        }
    };

    // Build view data with current version info for each node.
    let mut node_views = Vec::new();
    for node in &nodes {
        let current_version = Version::current_for(&data.db, node.id, main_branch.id)
            .await
            .unwrap_or(None);

        let title = current_version
            .as_ref()
            .map(|v| v.title.clone())
            .unwrap_or_default();
        let status = match &current_version {
            Some(v) if v.committed_at.is_some() => "Committed",
            Some(_) => "Draft",
            None => "Draft",
        };

        node_views.push(json!({
            "id": node.id,
            "title": title,
            "slug": &node.slug,
            "status": status,
            "updated_at": format_datetime(node.updated_at),
        }));
    }

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

// ---------------------------------------------------------------------------
// Admin content — Show
// ---------------------------------------------------------------------------

/// GET /admin/content/{id} — Show a single node with its current version.
pub async fn admin_content_show(
    data: web::Data<AppState>,
    path: web::Path<String>,
    req: HttpRequest,
) -> HttpResponse {
    let id = match parse_id(&path.into_inner()) {
        Some(id) => id,
        None => {
            return HttpResponse::NotFound()
                .content_type("text/plain")
                .body("Not Found");
        }
    };

    let node = match Node::find(&data.db, id).await {
        Ok(Some(node)) => node,
        Ok(None) | Err(_) => {
            return HttpResponse::NotFound()
                .content_type("text/plain")
                .body("Not Found");
        }
    };

    let main_branch = match Branch::find_by_name(&data.db, "main").await {
        Ok(Some(b)) => b,
        _ => {
            return HttpResponse::InternalServerError()
                .content_type("text/plain")
                .body("Main branch not found");
        }
    };

    let current_version = Version::current_for(&data.db, node.id, main_branch.id)
        .await
        .unwrap_or(None);

    let version_view = current_version.as_ref().map(|v| {
        json!({
            "title": &v.title,
            "body": v.body.as_deref().unwrap_or(""),
            "committed_at": v.committed_at.map(format_datetime),
            "commit_message": &v.commit_message,
            "is_uncommitted": v.committed_at.is_none(),
        })
    });

    let mut ctx = Context::new();
    ctx.insert("node", &json!({ "id": node.id, "slug": &node.slug }));
    ctx.insert("version", &version_view);

    render_page(
        &data.templates,
        "admin/content/show.html",
        &mut ctx,
        &req,
        StatusCode::OK,
    )
}

// ---------------------------------------------------------------------------
// Admin content — New
// ---------------------------------------------------------------------------

/// GET /admin/content/new — Display the new node form.
pub async fn admin_content_new(
    data: web::Data<AppState>,
    req: HttpRequest,
) -> HttpResponse {
    let mut ctx = Context::new();
    ctx.insert("node", &json!({ "slug": "" }));
    ctx.insert("version", &json!({ "title": "", "body": "" }));
    ctx.insert("errors", &json!({ "title": [], "slug": [] }));
    ctx.insert("error_messages", &Vec::<String>::new());

    render_page(
        &data.templates,
        "admin/content/new.html",
        &mut ctx,
        &req,
        StatusCode::OK,
    )
}

// ---------------------------------------------------------------------------
// Admin content — Create
// ---------------------------------------------------------------------------

/// POST /admin/content — Create a new node with its first version.
pub async fn admin_content_create(
    data: web::Data<AppState>,
    req: HttpRequest,
    form: web::Form<CreateFormData>,
) -> HttpResponse {
    let title = form.title.clone().unwrap_or_default();
    let slug = form.slug.clone().filter(|s| !s.is_empty());
    let body = form.body.clone().filter(|s| !s.is_empty());

    let params = CreateNodeWithVersion {
        title: title.clone(),
        slug: slug.clone(),
        body: body.clone(),
    };

    match Node::create_with_version(&data.db, params).await {
        Ok((node, _version)) => {
            redirect_with_notice(
                &format!("/admin/content/{}", node.id),
                "Node was successfully created.",
            )
        }
        Err(errors) => {
            let empty_vec = vec![];
            let error_messages = errors.full_messages();
            let title_errors = errors.get("title").unwrap_or(&empty_vec);
            let slug_errors = errors.get("slug").unwrap_or(&empty_vec);

            let mut ctx = Context::new();
            ctx.insert(
                "node",
                &json!({ "slug": slug.as_deref().unwrap_or("") }),
            );
            ctx.insert(
                "version",
                &json!({ "title": &title, "body": body.as_deref().unwrap_or("") }),
            );
            ctx.insert(
                "errors",
                &json!({ "title": title_errors, "slug": slug_errors }),
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

// ---------------------------------------------------------------------------
// Admin content — Edit
// ---------------------------------------------------------------------------

/// GET /admin/content/{id}/edit — Display the edit form with current version data.
pub async fn admin_content_edit(
    data: web::Data<AppState>,
    path: web::Path<String>,
    req: HttpRequest,
) -> HttpResponse {
    let id = match parse_id(&path.into_inner()) {
        Some(id) => id,
        None => {
            return HttpResponse::NotFound()
                .content_type("text/plain")
                .body("Not Found");
        }
    };

    let node = match Node::find(&data.db, id).await {
        Ok(Some(node)) => node,
        Ok(None) | Err(_) => {
            return HttpResponse::NotFound()
                .content_type("text/plain")
                .body("Not Found");
        }
    };

    let main_branch = match Branch::find_by_name(&data.db, "main").await {
        Ok(Some(b)) => b,
        _ => {
            return HttpResponse::InternalServerError()
                .content_type("text/plain")
                .body("Main branch not found");
        }
    };

    let current_version = Version::current_for(&data.db, node.id, main_branch.id)
        .await
        .unwrap_or(None);

    let title = current_version
        .as_ref()
        .map(|v| v.title.as_str())
        .unwrap_or("");
    let body = current_version
        .as_ref()
        .and_then(|v| v.body.as_deref())
        .unwrap_or("");

    let mut ctx = Context::new();
    ctx.insert("node", &json!({ "id": node.id, "slug": &node.slug }));
    ctx.insert("version", &json!({ "title": title, "body": body }));
    ctx.insert("errors", &json!({ "title": [] }));
    ctx.insert("error_messages", &Vec::<String>::new());

    render_page(
        &data.templates,
        "admin/content/edit.html",
        &mut ctx,
        &req,
        StatusCode::OK,
    )
}

// ---------------------------------------------------------------------------
// Admin content — Update (Save Draft)
// ---------------------------------------------------------------------------

/// PATCH /admin/content/{id} — Save a draft (create or update uncommitted version).
pub async fn admin_content_update(
    data: web::Data<AppState>,
    path: web::Path<String>,
    req: HttpRequest,
    title: String,
    body: Option<String>,
) -> HttpResponse {
    let id = match parse_id(&path.into_inner()) {
        Some(id) => id,
        None => {
            return HttpResponse::NotFound()
                .content_type("text/plain")
                .body("Not Found");
        }
    };

    let node = match Node::find(&data.db, id).await {
        Ok(Some(node)) => node,
        Ok(None) | Err(_) => {
            return HttpResponse::NotFound()
                .content_type("text/plain")
                .body("Not Found");
        }
    };

    let main_branch = match Branch::find_by_name(&data.db, "main").await {
        Ok(Some(b)) => b,
        _ => {
            return HttpResponse::InternalServerError()
                .content_type("text/plain")
                .body("Main branch not found");
        }
    };

    // Check for an existing uncommitted version
    let existing_uncommitted = Version::find_uncommitted(&data.db, node.id, main_branch.id)
        .await
        .unwrap_or(None);

    let result = if let Some(existing) = existing_uncommitted {
        // Update the existing draft
        existing
            .update(
                &data.db,
                UpdateVersion {
                    title: title.clone(),
                    body: body.clone(),
                },
            )
            .await
    } else {
        // Create a new uncommitted version, with parent pointing to latest committed
        let parent = Version::latest_committed(&data.db, node.id, main_branch.id)
            .await
            .unwrap_or(None);

        Version::create(
            &data.db,
            NewVersion {
                node_id: node.id,
                branch_id: main_branch.id,
                parent_version_id: parent.map(|p| p.id),
                title: title.clone(),
                body: body.clone(),
            },
        )
        .await
    };

    match result {
        Ok(_) => {
            redirect_with_notice(
                &format!("/admin/content/{}", node.id),
                "Draft was successfully saved.",
            )
        }
        Err(errors) => {
            let empty_vec = vec![];
            let error_messages = errors.full_messages();
            let title_errors = errors.get("title").unwrap_or(&empty_vec);

            let mut ctx = Context::new();
            ctx.insert("node", &json!({ "id": node.id, "slug": &node.slug }));
            ctx.insert(
                "version",
                &json!({
                    "title": &title,
                    "body": body.as_deref().unwrap_or(""),
                }),
            );
            ctx.insert("errors", &json!({ "title": title_errors }));
            ctx.insert("error_messages", &error_messages);

            render_page(
                &data.templates,
                "admin/content/edit.html",
                &mut ctx,
                &req,
                StatusCode::UNPROCESSABLE_ENTITY,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Admin content — Commit
// ---------------------------------------------------------------------------

/// POST /admin/content/{id}/commit — Commit an uncommitted version.
pub async fn admin_content_commit(
    data: web::Data<AppState>,
    path: web::Path<String>,
    form: web::Form<CommitFormData>,
) -> HttpResponse {
    let id = match parse_id(&path.into_inner()) {
        Some(id) => id,
        None => {
            return HttpResponse::NotFound()
                .content_type("text/plain")
                .body("Not Found");
        }
    };

    let node = match Node::find(&data.db, id).await {
        Ok(Some(node)) => node,
        Ok(None) | Err(_) => {
            return HttpResponse::NotFound()
                .content_type("text/plain")
                .body("Not Found");
        }
    };

    let main_branch = match Branch::find_by_name(&data.db, "main").await {
        Ok(Some(b)) => b,
        _ => {
            return HttpResponse::InternalServerError()
                .content_type("text/plain")
                .body("Main branch not found");
        }
    };

    let uncommitted = match Version::find_uncommitted(&data.db, node.id, main_branch.id).await {
        Ok(Some(v)) => v,
        _ => {
            return redirect_with_alert(
                &format!("/admin/content/{}", node.id),
                "No uncommitted changes to commit.",
            );
        }
    };

    let message = form.commit_message.clone().unwrap_or_default();
    let message = message.trim();

    if message.is_empty() {
        return redirect_with_alert(
            &format!("/admin/content/{}", node.id),
            "Commit message can't be blank.",
        );
    }

    match uncommitted.commit(&data.db, message).await {
        Ok(_) => redirect_with_notice(
            &format!("/admin/content/{}", node.id),
            "Version was successfully committed.",
        ),
        Err(_) => redirect_with_alert(
            &format!("/admin/content/{}", node.id),
            "Failed to commit version.",
        ),
    }
}

// ---------------------------------------------------------------------------
// Admin content — Destroy
// ---------------------------------------------------------------------------

/// DELETE /admin/content/{id} — Delete a node (cascades to versions).
pub async fn admin_content_destroy(
    data: web::Data<AppState>,
    path: web::Path<String>,
) -> HttpResponse {
    let id = match parse_id(&path.into_inner()) {
        Some(id) => id,
        None => {
            return HttpResponse::NotFound()
                .content_type("text/plain")
                .body("Not Found");
        }
    };

    match Node::delete(&data.db, id).await {
        Ok(true) => {
            redirect_with_notice("/admin/content", "Node was successfully deleted.")
        }
        Ok(false) => HttpResponse::NotFound()
            .content_type("text/plain")
            .body("Not Found"),
        Err(_) => HttpResponse::InternalServerError()
            .content_type("text/plain")
            .body("Database error"),
    }
}

// ---------------------------------------------------------------------------
// Method override handler
// ---------------------------------------------------------------------------

/// POST /admin/content/{id} — Method override handler.
///
/// HTML forms only support GET and POST, so we use a hidden `_method` field
/// to tunnel DELETE and PATCH requests. This handler reads that field and
/// delegates to the appropriate action.
pub async fn admin_content_method_override(
    data: web::Data<AppState>,
    path: web::Path<String>,
    req: HttpRequest,
    form: web::Form<MethodOverrideForm>,
) -> HttpResponse {
    match form.method.as_deref() {
        Some("delete") => admin_content_destroy(data, path).await,
        Some("patch") => {
            let title = form.title.clone().unwrap_or_default();
            let body = form.body.clone().filter(|s| !s.is_empty());
            admin_content_update(data, path, req, title, body).await
        }
        _ => HttpResponse::NotFound()
            .content_type("text/plain")
            .body("Not Found"),
    }
}
