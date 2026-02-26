use chrono::NaiveDateTime;
use regex::Regex;
use sqlx::SqlitePool;
use std::collections::HashMap;
use std::sync::LazyLock;

use super::branch::Branch;
use super::version::{NewVersion, Version};

/// Regex for valid slug format: lowercase alphanumeric segments separated by single hyphens.
/// Equivalent to the Rails validation: /\A[a-z0-9]+(-[a-z0-9]+)*\z/
static SLUG_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^[a-z0-9]+(-[a-z0-9]+)*$").unwrap());

/// Regex used during slug generation to replace non-alphanumeric characters.
static NON_ALNUM_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"[^a-z0-9]").unwrap());

/// Regex used during slug generation to collapse consecutive hyphens.
static MULTI_HYPHEN_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"-{2,}").unwrap());

// ---------------------------------------------------------------------------
// Domain types
// ---------------------------------------------------------------------------

/// A Node as stored in the database. After VERS-01, nodes only hold identity
/// (slug) — content (title, body) lives in the `versions` table.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct Node {
    pub id: i64,
    pub slug: String,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
}

/// Parameters for creating a new node with its first version (atomic operation).
#[derive(Debug)]
pub struct CreateNodeWithVersion {
    pub title: String,
    pub slug: Option<String>,
    pub body: Option<String>,
}

/// Validation errors keyed by field name, each with a list of messages.
/// Analogous to Rails' `ActiveModel::Errors`.
#[derive(Debug, Default)]
pub struct ValidationErrors {
    errors: HashMap<String, Vec<String>>,
}

impl ValidationErrors {
    pub fn add(&mut self, field: &str, message: &str) {
        self.errors
            .entry(field.to_string())
            .or_default()
            .push(message.to_string());
    }

    pub fn is_empty(&self) -> bool {
        self.errors.is_empty()
    }

    pub fn get(&self, field: &str) -> Option<&Vec<String>> {
        self.errors.get(field)
    }

    pub fn all(&self) -> &HashMap<String, Vec<String>> {
        &self.errors
    }

    /// Merge another set of errors into this one.
    pub fn merge(&mut self, other: &ValidationErrors) {
        for (field, messages) in &other.errors {
            for msg in messages {
                self.add(field, msg);
            }
        }
    }

    /// Return error messages prefixed by their capitalized field name,
    /// e.g. "Title can't be blank". Mirrors Rails' `errors.full_messages`.
    pub fn full_messages(&self) -> Vec<String> {
        self.errors
            .iter()
            .flat_map(|(field, msgs)| {
                let capitalized = {
                    let mut chars = field.chars();
                    match chars.next() {
                        Some(c) => c.to_uppercase().to_string() + chars.as_str(),
                        None => String::new(),
                    }
                };
                msgs.iter()
                    .map(move |msg| format!("{capitalized} {msg}"))
            })
            .collect()
    }
}

impl std::fmt::Display for ValidationErrors {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        for (field, messages) in &self.errors {
            for msg in messages {
                writeln!(f, "{field} {msg}")?;
            }
        }
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// Slug generation
// ---------------------------------------------------------------------------

/// Derives a URL-safe slug from a title, following the same algorithm as the
/// Rails implementation:
///
/// 1. Downcase the title.
/// 2. Replace any non-alphanumeric character with a hyphen.
/// 3. Collapse consecutive hyphens into one.
/// 4. Strip leading and trailing hyphens.
pub fn generate_slug(title: &str) -> String {
    let lower = title.to_lowercase();
    let replaced = NON_ALNUM_RE.replace_all(&lower, "-");
    let collapsed = MULTI_HYPHEN_RE.replace_all(&replaced, "-");
    collapsed.trim_matches('-').to_string()
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

/// Validates slug fields for a node. Title validation has moved to Version.
async fn validate_slug(
    pool: &SqlitePool,
    slug: &str,
    existing_id: Option<i64>,
) -> ValidationErrors {
    let mut errors = ValidationErrors::default();

    if slug.is_empty() {
        errors.add("slug", "can't be blank");
    } else {
        if slug.len() > 255 {
            errors.add("slug", "is too long (maximum is 255 characters)");
        }
        if !SLUG_RE.is_match(slug) {
            errors.add("slug", "is invalid");
        }
        // Check uniqueness (case-insensitive)
        let duplicate_exists = match existing_id {
            Some(id) => {
                sqlx::query_scalar::<_, i64>(
                    "SELECT COUNT(*) FROM nodes WHERE LOWER(slug) = LOWER(?) AND id != ?",
                )
                .bind(slug)
                .bind(id)
                .fetch_one(pool)
                .await
                .unwrap_or(0)
                    > 0
            }
            None => {
                sqlx::query_scalar::<_, i64>(
                    "SELECT COUNT(*) FROM nodes WHERE LOWER(slug) = LOWER(?)",
                )
                .bind(slug)
                .fetch_one(pool)
                .await
                .unwrap_or(0)
                    > 0
            }
        };
        if duplicate_exists {
            errors.add("slug", "has already been taken");
        }
    }

    errors
}

// ---------------------------------------------------------------------------
// Persistence
// ---------------------------------------------------------------------------

impl Node {
    /// Fetch all nodes ordered by `updated_at` descending (for the admin listing).
    pub async fn all_ordered(pool: &SqlitePool) -> Result<Vec<Node>, sqlx::Error> {
        sqlx::query_as::<_, Node>("SELECT * FROM nodes ORDER BY updated_at DESC")
            .fetch_all(pool)
            .await
    }

    /// Find a node by its primary key. Returns `None` if not found.
    pub async fn find(pool: &SqlitePool, id: i64) -> Result<Option<Node>, sqlx::Error> {
        sqlx::query_as::<_, Node>("SELECT * FROM nodes WHERE id = ?")
            .bind(id)
            .fetch_optional(pool)
            .await
    }

    /// Create a new node together with its first (uncommitted) version on the
    /// main branch. This is an atomic operation — if either the node or version
    /// fails validation, nothing is persisted.
    ///
    /// Mirrors Rails' `Node.create_with_version(title:, slug:, body:)`.
    pub async fn create_with_version(
        pool: &SqlitePool,
        params: CreateNodeWithVersion,
    ) -> Result<(Node, Version), ValidationErrors> {
        // Auto-generate slug from title when slug is blank/absent
        let slug = match &params.slug {
            Some(s) if !s.is_empty() => s.clone(),
            _ => generate_slug(&params.title),
        };

        // Validate slug
        let slug_errors = validate_slug(pool, &slug, None).await;

        // Validate title (Version-level validation)
        let title_errors = super::version::validate_version(&params.title);

        // Combine errors from both node and version validation
        let mut all_errors = ValidationErrors::default();
        all_errors.merge(&slug_errors);
        all_errors.merge(&title_errors);

        if !all_errors.is_empty() {
            return Err(all_errors);
        }

        let now = chrono::Utc::now().naive_utc();

        // Find the main branch
        let main_branch = Branch::find_by_name(pool, "main")
            .await
            .map_err(|e| {
                let mut errors = ValidationErrors::default();
                errors.add("base", &format!("database error: {e}"));
                errors
            })?
            .ok_or_else(|| {
                let mut errors = ValidationErrors::default();
                errors.add("base", "main branch not found");
                errors
            })?;

        // Insert node
        let node_id = sqlx::query_scalar::<_, i64>(
            "INSERT INTO nodes (slug, created_at, updated_at) VALUES (?, ?, ?) RETURNING id",
        )
        .bind(&slug)
        .bind(now)
        .bind(now)
        .fetch_one(pool)
        .await
        .map_err(|e| {
            let mut errors = ValidationErrors::default();
            errors.add("base", &format!("database error: {e}"));
            errors
        })?;

        // Insert first uncommitted version on main
        let version = Version::create(
            pool,
            NewVersion {
                node_id,
                branch_id: main_branch.id,
                parent_version_id: None,
                title: params.title,
                body: params.body,
            },
        )
        .await?;

        let node = Node::find(pool, node_id)
            .await
            .map_err(|e| {
                let mut errors = ValidationErrors::default();
                errors.add("base", &format!("failed to reload node: {e}"));
                errors
            })?
            .ok_or_else(|| {
                let mut errors = ValidationErrors::default();
                errors.add("base", "failed to reload node after insert");
                errors
            })?;

        Ok((node, version))
    }

    /// Delete a node by its primary key. Cascades to all versions (via FK).
    /// Returns true if a row was deleted.
    pub async fn delete(pool: &SqlitePool, id: i64) -> Result<bool, sqlx::Error> {
        let result = sqlx::query("DELETE FROM nodes WHERE id = ?")
            .bind(id)
            .execute(pool)
            .await?;
        Ok(result.rows_affected() > 0)
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use sqlx::SqlitePool;

    /// Create an in-memory SQLite database with the new versioned schema.
    async fn test_pool() -> SqlitePool {
        let pool = SqlitePool::connect("sqlite::memory:")
            .await
            .expect("failed to create in-memory pool");

        // Enable foreign keys for SQLite
        sqlx::query("PRAGMA foreign_keys = ON")
            .execute(&pool)
            .await
            .expect("failed to enable foreign keys");

        sqlx::query(
            "CREATE TABLE nodes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                slug TEXT NOT NULL,
                created_at DATETIME NOT NULL,
                updated_at DATETIME NOT NULL
            )",
        )
        .execute(&pool)
        .await
        .expect("failed to create nodes table");

        sqlx::query("CREATE UNIQUE INDEX index_nodes_on_slug ON nodes (slug)")
            .execute(&pool)
            .await
            .expect("failed to create slug index");

        sqlx::query(
            "CREATE TABLE branches (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                created_at DATETIME NOT NULL,
                updated_at DATETIME NOT NULL
            )",
        )
        .execute(&pool)
        .await
        .expect("failed to create branches table");

        sqlx::query("CREATE UNIQUE INDEX index_branches_on_name ON branches (name)")
            .execute(&pool)
            .await
            .expect("failed to create branch name index");

        // Seed the main and published branches
        sqlx::query(
            "INSERT INTO branches (name, created_at, updated_at)
             VALUES ('main', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
                    ('published', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)",
        )
        .execute(&pool)
        .await
        .expect("failed to seed branches");

        sqlx::query(
            "CREATE TABLE versions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                node_id INTEGER NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
                branch_id INTEGER NOT NULL REFERENCES branches(id) ON DELETE RESTRICT,
                parent_version_id INTEGER REFERENCES versions(id) ON DELETE SET NULL,
                source_version_id INTEGER REFERENCES versions(id) ON DELETE SET NULL,
                title TEXT NOT NULL,
                body TEXT,
                commit_message TEXT,
                committed_at DATETIME,
                created_at DATETIME NOT NULL,
                updated_at DATETIME NOT NULL
            )",
        )
        .execute(&pool)
        .await
        .expect("failed to create versions table");

        sqlx::query(
            "CREATE UNIQUE INDEX index_versions_uncommitted_unique
             ON versions (node_id, branch_id) WHERE committed_at IS NULL",
        )
        .execute(&pool)
        .await
        .expect("failed to create uncommitted unique index");

        pool
    }

    // -- Slug generation -----------------------------------------------------

    #[test]
    fn generates_slug_from_title() {
        assert_eq!(generate_slug("Hello World"), "hello-world");
    }

    #[test]
    fn downcases_the_title() {
        assert_eq!(generate_slug("UPPERCASE TITLE"), "uppercase-title");
    }

    #[test]
    fn replaces_non_alphanumeric_with_hyphens() {
        assert_eq!(
            generate_slug("Hello, World! How's it going?"),
            "hello-world-how-s-it-going"
        );
    }

    #[test]
    fn collapses_consecutive_hyphens() {
        assert_eq!(generate_slug("hello---world"), "hello-world");
    }

    #[test]
    fn strips_leading_and_trailing_hyphens() {
        assert_eq!(generate_slug("  Hello World  "), "hello-world");
    }

    #[test]
    fn returns_empty_for_all_punctuation() {
        assert_eq!(generate_slug("!!!"), "");
    }

    // -- Node.create_with_version -------------------------------------------

    #[tokio::test]
    async fn creates_node_and_version() {
        let pool = test_pool().await;
        let (node, version) = Node::create_with_version(
            &pool,
            CreateNodeWithVersion {
                title: "Hello World".into(),
                slug: None,
                body: None,
            },
        )
        .await
        .unwrap();

        assert_eq!(node.slug, "hello-world");
        assert_eq!(version.title, "Hello World");
        assert_eq!(version.node_id, node.id);
        assert!(version.committed_at.is_none()); // uncommitted
    }

    #[tokio::test]
    async fn uses_explicit_slug() {
        let pool = test_pool().await;
        let (node, _version) = Node::create_with_version(
            &pool,
            CreateNodeWithVersion {
                title: "Hello World".into(),
                slug: Some("custom-slug".into()),
                body: None,
            },
        )
        .await
        .unwrap();
        assert_eq!(node.slug, "custom-slug");
    }

    #[tokio::test]
    async fn stores_body_on_version() {
        let pool = test_pool().await;
        let (_node, version) = Node::create_with_version(
            &pool,
            CreateNodeWithVersion {
                title: "Hello".into(),
                slug: None,
                body: Some("Some content".into()),
            },
        )
        .await
        .unwrap();
        assert_eq!(version.body.as_deref(), Some("Some content"));
    }

    #[tokio::test]
    async fn rejects_blank_title() {
        let pool = test_pool().await;
        let result = Node::create_with_version(
            &pool,
            CreateNodeWithVersion {
                title: "".into(),
                slug: None,
                body: None,
            },
        )
        .await;
        assert!(result.is_err());
        let errors = result.unwrap_err();
        assert!(errors
            .get("title")
            .unwrap()
            .contains(&"can't be blank".to_string()));
    }

    #[tokio::test]
    async fn rejects_duplicate_slug() {
        let pool = test_pool().await;
        Node::create_with_version(
            &pool,
            CreateNodeWithVersion {
                title: "First".into(),
                slug: Some("taken".into()),
                body: None,
            },
        )
        .await
        .unwrap();

        let result = Node::create_with_version(
            &pool,
            CreateNodeWithVersion {
                title: "Second".into(),
                slug: Some("taken".into()),
                body: None,
            },
        )
        .await;
        assert!(result.is_err());
        assert!(result
            .unwrap_err()
            .get("slug")
            .unwrap()
            .contains(&"has already been taken".to_string()));
    }

    #[tokio::test]
    async fn rejects_invalid_slug_formats() {
        let pool = test_pool().await;
        let invalid_slugs = [
            "Hello",
            "hello world",
            "hello--world",
            "-hello",
            "hello-",
            "UPPER",
            "hello_world",
        ];
        for bad_slug in &invalid_slugs {
            let result = Node::create_with_version(
                &pool,
                CreateNodeWithVersion {
                    title: "Something".into(),
                    slug: Some(bad_slug.to_string()),
                    body: None,
                },
            )
            .await;
            assert!(result.is_err(), "Expected slug '{bad_slug}' to be invalid");
        }
    }

    #[tokio::test]
    async fn accepts_valid_slug_formats() {
        let pool = test_pool().await;
        let valid_slugs = ["hello", "hello-world", "a1-b2-c3", "123"];
        for good_slug in &valid_slugs {
            let result = Node::create_with_version(
                &pool,
                CreateNodeWithVersion {
                    title: format!("Title for {good_slug}"),
                    slug: Some(good_slug.to_string()),
                    body: None,
                },
            )
            .await;
            assert!(result.is_ok(), "Expected slug '{good_slug}' to be valid");
        }
    }

    #[tokio::test]
    async fn fails_when_title_produces_empty_slug() {
        let pool = test_pool().await;
        let result = Node::create_with_version(
            &pool,
            CreateNodeWithVersion {
                title: "!!!".into(),
                slug: None,
                body: None,
            },
        )
        .await;
        assert!(result.is_err());
        assert!(result
            .unwrap_err()
            .get("slug")
            .unwrap()
            .contains(&"can't be blank".to_string()));
    }

    // -- Version operations -------------------------------------------------

    #[tokio::test]
    async fn current_for_returns_uncommitted_version() {
        let pool = test_pool().await;
        let (node, version) = Node::create_with_version(
            &pool,
            CreateNodeWithVersion {
                title: "Test".into(),
                slug: None,
                body: None,
            },
        )
        .await
        .unwrap();

        let main = Branch::find_by_name(&pool, "main").await.unwrap().unwrap();
        let current = Version::current_for(&pool, node.id, main.id)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(current.id, version.id);
        assert!(current.committed_at.is_none());
    }

    #[tokio::test]
    async fn commit_transitions_version() {
        let pool = test_pool().await;
        let (_node, version) = Node::create_with_version(
            &pool,
            CreateNodeWithVersion {
                title: "Test".into(),
                slug: None,
                body: None,
            },
        )
        .await
        .unwrap();

        let committed = version.commit(&pool, "Initial commit").await.unwrap();
        assert!(committed.committed_at.is_some());
        assert_eq!(committed.commit_message.as_deref(), Some("Initial commit"));
    }

    #[tokio::test]
    async fn delete_cascades_to_versions() {
        let pool = test_pool().await;
        let (node, _version) = Node::create_with_version(
            &pool,
            CreateNodeWithVersion {
                title: "Doomed".into(),
                slug: None,
                body: None,
            },
        )
        .await
        .unwrap();

        let count_before: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM versions")
                .fetch_one(&pool)
                .await
                .unwrap();
        assert_eq!(count_before, 1);

        Node::delete(&pool, node.id).await.unwrap();

        let count_after: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM versions")
                .fetch_one(&pool)
                .await
                .unwrap();
        assert_eq!(count_after, 0);
    }

    #[tokio::test]
    async fn delete_returns_false_for_missing_node() {
        let pool = test_pool().await;
        let deleted = Node::delete(&pool, 999).await.unwrap();
        assert!(!deleted);
    }
}
