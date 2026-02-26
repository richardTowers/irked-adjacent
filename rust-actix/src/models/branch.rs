use chrono::NaiveDateTime;
use sqlx::SqlitePool;

// ---------------------------------------------------------------------------
// Domain types
// ---------------------------------------------------------------------------

/// A branch represents a named line of content versions (e.g. "main", "published").
/// Branch management UI was removed — only the seeded "main" and "published"
/// branches are used. "main" holds working/committed content; "published" holds
/// the public-facing snapshots.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct Branch {
    pub id: i64,
    pub name: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
}

impl Branch {
    /// Find a branch by its exact name.
    pub async fn find_by_name(
        pool: &SqlitePool,
        name: &str,
    ) -> Result<Option<Branch>, sqlx::Error> {
        sqlx::query_as::<_, Branch>("SELECT * FROM branches WHERE name = ?")
            .bind(name)
            .fetch_optional(pool)
            .await
    }
}
