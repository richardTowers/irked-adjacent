use actix_web::{web, App, HttpServer, middleware};
use sqlx::sqlite::SqlitePoolOptions;
use tera::Tera;

mod config;
mod models;
mod routes;

pub struct AppState {
    pub db: sqlx::SqlitePool,
    pub templates: Tera,
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    dotenvy::dotenv().ok();
    env_logger::init();

    let database_url = config::database_url();
    let host = config::host();
    let port = config::port();

    let pool = SqlitePoolOptions::new()
        .max_connections(5)
        .connect(&database_url)
        .await
        .expect("Failed to create database pool");

    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .expect("Failed to run database migrations");

    let templates = Tera::new("templates/**/*").expect("Failed to parse templates");

    log::info!("Starting server at http://{}:{}", host, port);

    HttpServer::new(move || {
        App::new()
            .app_data(web::Data::new(AppState {
                db: pool.clone(),
                templates: templates.clone(),
            }))
            .wrap(middleware::Logger::default())
            .route("/", web::get().to(routes::root_redirect))
            .route("/up", web::get().to(routes::health_check))
            .route("/admin/content", web::get().to(routes::admin_content_index))
            .route("/admin/content/{id}", web::get().to(routes::admin_content_show))
    })
    .bind((host.as_str(), port))?
    .run()
    .await
}
