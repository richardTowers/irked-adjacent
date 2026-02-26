use chrono::NaiveDateTime;
use sqlx::SqlitePool;

use super::node::ValidationErrors;

// ---------------------------------------------------------------------------
// Domain types
// ---------------------------------------------------------------------------

/// A Version as stored in the database. Content (title, body) lives here
/// rather than on Node, enabling a git-like branching/versioning model.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct Version {
    pub id: i64,
    pub node_id: i64,
    pub branch_id: i64,
    pub parent_version_id: Option<i64>,
    pub source_version_id: Option<i64>,
    pub title: String,
    pub body: Option<String>,
    pub commit_message: Option<String>,
    pub committed_at: Option<NaiveDateTime>,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
}

/// Parameters for creating a new uncommitted version.
#[derive(Debug)]
pub struct NewVersion {
    pub node_id: i64,
    pub branch_id: i64,
    pub parent_version_id: Option<i64>,
    pub title: String,
    pub body: Option<String>,
}

/// Parameters for updating an existing uncommitted version.
#[derive(Debug)]
pub struct UpdateVersion {
    pub title: String,
    pub body: Option<String>,
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

/// Validate version fields for creation. Only validates the content fields;
/// structural constraints (uncommitted uniqueness, lineage) are enforced by
/// the database or by the calling code.
pub fn validate_version(title: &str) -> ValidationErrors {
    let mut errors = ValidationErrors::default();

    if title.is_empty() {
        errors.add("title", "can't be blank");
    } else if title.len() > 255 {
        errors.add("title", "is too long (maximum is 255 characters)");
    }

    errors
}

// ---------------------------------------------------------------------------
// Persistence
// ---------------------------------------------------------------------------

impl Version {
    /// Resolve the "current" version for a node on a branch.
    ///
    /// Priority: uncommitted version > latest committed version > None.
    /// This mirrors Rails' `Version.current_for(node, branch)`.
    pub async fn current_for(
        pool: &SqlitePool,
        node_id: i64,
        branch_id: i64,
    ) -> Result<Option<Version>, sqlx::Error> {
        // First check for an uncommitted version
        let uncommitted = sqlx::query_as::<_, Version>(
            "SELECT * FROM versions
             WHERE node_id = ? AND branch_id = ? AND committed_at IS NULL
             LIMIT 1",
        )
        .bind(node_id)
        .bind(branch_id)
        .fetch_optional(pool)
        .await?;

        if uncommitted.is_some() {
            return Ok(uncommitted);
        }

        // Fall back to latest committed version
        sqlx::query_as::<_, Version>(
            "SELECT * FROM versions
             WHERE node_id = ? AND branch_id = ? AND committed_at IS NOT NULL
             ORDER BY committed_at DESC
             LIMIT 1",
        )
        .bind(node_id)
        .bind(branch_id)
        .fetch_optional(pool)
        .await
    }

    /// Find an uncommitted version for a given node and branch.
    pub async fn find_uncommitted(
        pool: &SqlitePool,
        node_id: i64,
        branch_id: i64,
    ) -> Result<Option<Version>, sqlx::Error> {
        sqlx::query_as::<_, Version>(
            "SELECT * FROM versions
             WHERE node_id = ? AND branch_id = ? AND committed_at IS NULL
             LIMIT 1",
        )
        .bind(node_id)
        .bind(branch_id)
        .fetch_optional(pool)
        .await
    }

    /// Find the latest committed version for a given node and branch.
    pub async fn latest_committed(
        pool: &SqlitePool,
        node_id: i64,
        branch_id: i64,
    ) -> Result<Option<Version>, sqlx::Error> {
        sqlx::query_as::<_, Version>(
            "SELECT * FROM versions
             WHERE node_id = ? AND branch_id = ? AND committed_at IS NOT NULL
             ORDER BY committed_at DESC
             LIMIT 1",
        )
        .bind(node_id)
        .bind(branch_id)
        .fetch_optional(pool)
        .await
    }

    /// Create a new uncommitted version. Validates title before inserting.
    pub async fn create(
        pool: &SqlitePool,
        params: NewVersion,
    ) -> Result<Version, ValidationErrors> {
        let errors = validate_version(&params.title);
        if !errors.is_empty() {
            return Err(errors);
        }

        let now = chrono::Utc::now().naive_utc();

        let id = sqlx::query_scalar::<_, i64>(
            "INSERT INTO versions (node_id, branch_id, parent_version_id, title, body, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?)
             RETURNING id",
        )
        .bind(params.node_id)
        .bind(params.branch_id)
        .bind(params.parent_version_id)
        .bind(&params.title)
        .bind(&params.body)
        .bind(now)
        .bind(now)
        .fetch_one(pool)
        .await
        .map_err(|e| {
            let mut errors = ValidationErrors::default();
            errors.add("base", &format!("database error: {e}"));
            errors
        })?;

        Self::find(pool, id).await.map_err(|e| {
            let mut errors = ValidationErrors::default();
            errors.add("base", &format!("failed to reload version: {e}"));
            errors
        })
    }

    /// Update an existing uncommitted version's content fields.
    /// Returns an error if the version has already been committed (immutability).
    pub async fn update(
        &self,
        pool: &SqlitePool,
        params: UpdateVersion,
    ) -> Result<Version, ValidationErrors> {
        if self.committed_at.is_some() {
            let mut errors = ValidationErrors::default();
            errors.add("base", "committed versions are immutable");
            return Err(errors);
        }

        let errors = validate_version(&params.title);
        if !errors.is_empty() {
            return Err(errors);
        }

        let now = chrono::Utc::now().naive_utc();

        sqlx::query(
            "UPDATE versions SET title = ?, body = ?, updated_at = ? WHERE id = ?",
        )
        .bind(&params.title)
        .bind(&params.body)
        .bind(now)
        .bind(self.id)
        .execute(pool)
        .await
        .map_err(|e| {
            let mut errors = ValidationErrors::default();
            errors.add("base", &format!("database error: {e}"));
            errors
        })?;

        Self::find(pool, self.id).await.map_err(|e| {
            let mut errors = ValidationErrors::default();
            errors.add("base", &format!("failed to reload version: {e}"));
            errors
        })
    }

    /// Transition this version from uncommitted to committed.
    /// Sets `commit_message` and `committed_at`, making the version immutable.
    pub async fn commit(
        &self,
        pool: &SqlitePool,
        message: &str,
    ) -> Result<Version, ValidationErrors> {
        if self.committed_at.is_some() {
            let mut errors = ValidationErrors::default();
            errors.add("base", "version is already committed");
            return Err(errors);
        }

        if message.is_empty() {
            let mut errors = ValidationErrors::default();
            errors.add("commit_message", "can't be blank");
            return Err(errors);
        }

        let now = chrono::Utc::now().naive_utc();

        sqlx::query(
            "UPDATE versions SET commit_message = ?, committed_at = ?, updated_at = ? WHERE id = ?",
        )
        .bind(message)
        .bind(now)
        .bind(now)
        .bind(self.id)
        .execute(pool)
        .await
        .map_err(|e| {
            let mut errors = ValidationErrors::default();
            errors.add("base", &format!("database error: {e}"));
            errors
        })?;

        Self::find(pool, self.id).await.map_err(|e| {
            let mut errors = ValidationErrors::default();
            errors.add("base", &format!("failed to reload version: {e}"));
            errors
        })
    }

    /// Find a version by its primary key.
    async fn find(pool: &SqlitePool, id: i64) -> Result<Version, sqlx::Error> {
        sqlx::query_as::<_, Version>("SELECT * FROM versions WHERE id = ?")
            .bind(id)
            .fetch_one(pool)
            .await
    }
}
