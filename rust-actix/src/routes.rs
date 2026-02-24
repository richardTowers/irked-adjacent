use actix_web::{web, HttpResponse};

use crate::AppState;

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
