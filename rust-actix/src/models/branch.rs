use chrono::NaiveDateTime;
use regex::Regex;
use sqlx::SqlitePool;
use std::sync::LazyLock;

use super::node::ValidationErrors;

/// Same format as slugs: lowercase alphanumeric segments separated by single hyphens.
static BRANCH_NAME_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^[a-z0-9]+(-[a-z0-9]+)*$").unwrap());

/// Names of branches that cannot be deleted or renamed.
const PROTECTED_NAMES: &[&str] = &["main", "published"];

// ---------------------------------------------------------------------------
// Domain types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct Branch {
    pub id: i64,
    pub name: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
}

impl Branch {
    /// Find a branch by its exact name.
    pub async fn find_by_name(pool: &SqlitePool, name: &str) -> Result<Option<Branch>, sqlx::Error> {
        sqlx::query_as::<_, Branch>("SELECT * FROM branches WHERE name = ?")
            .bind(name)
            .fetch_optional(pool)
            .await
    }

    /// Returns true if this branch is protected (main or published).
    pub fn is_protected(&self) -> bool {
        PROTECTED_NAMES.contains(&self.name.as_str())
    }
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

/// Validate a branch name. Returns errors if invalid.
pub fn validate_branch_name(name: &str) -> ValidationErrors {
    let mut errors = ValidationErrors::default();

    if name.is_empty() {
        errors.add("name", "can't be blank");
    } else {
        if name.len() > 50 {
            errors.add("name", "is too long (maximum is 50 characters)");
        }
        if !BRANCH_NAME_RE.is_match(name) {
            errors.add("name", "is invalid");
        }
    }

    errors
}
