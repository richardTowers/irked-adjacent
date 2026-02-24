use std::env;

pub fn database_url() -> String {
    env::var("DATABASE_URL").unwrap_or_else(|_| "sqlite:storage/development.sqlite3?mode=rwc".into())
}

pub fn host() -> String {
    env::var("HOST").unwrap_or_else(|_| "127.0.0.1".into())
}

pub fn port() -> u16 {
    env::var("PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(3001)
}
