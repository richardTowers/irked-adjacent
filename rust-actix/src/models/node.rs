use chrono::NaiveDateTime;
use regex::Regex;
use sqlx::SqlitePool;
use std::collections::HashMap;
use std::sync::LazyLock;

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

/// A Node as stored in the database (all fields populated).
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct Node {
    pub id: i64,
    pub title: String,
    pub slug: String,
    pub body: Option<String>,
    pub published: bool,
    pub published_at: Option<NaiveDateTime>,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
}

/// Parameters for creating a new node. Only the fields that callers are allowed
/// to set — mirrors Rails' strong parameters (`title`, `slug`, `body`, `published`).
#[derive(Debug, Default)]
pub struct NewNode {
    pub title: String,
    pub slug: Option<String>,
    pub body: Option<String>,
    pub published: bool,
}

/// Parameters for updating an existing node. Same permitted fields as creation.
#[derive(Debug)]
pub struct UpdateNode {
    pub title: String,
    pub slug: Option<String>,
    pub body: Option<String>,
    pub published: bool,
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

/// Validates fields for a node (used by both create and update paths).
/// The `slug` passed in should already have auto-generation applied.
/// `existing_id` is `Some(id)` when updating, so the uniqueness check can
/// exclude the node being updated.
async fn validate_node(
    pool: &SqlitePool,
    title: &str,
    slug: &str,
    existing_id: Option<i64>,
) -> ValidationErrors {
    let mut errors = ValidationErrors::default();

    // Title validations
    if title.is_empty() {
        errors.add("title", "can't be blank");
    } else if title.len() > 255 {
        errors.add("title", "is too long (maximum is 255 characters)");
    }

    // Slug validations
    if slug.is_empty() {
        errors.add("slug", "can't be blank");
    } else {
        if slug.len() > 255 {
            errors.add("slug", "is too long (maximum is 255 characters)");
        }
        if !SLUG_RE.is_match(slug) {
            errors.add("slug", "is invalid");
        }
        // Check uniqueness (case-insensitive) — must hit the database, like Rails.
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

    /// Create a new node. Applies slug auto-generation and published_at logic,
    /// then validates. Returns the persisted `Node` or `ValidationErrors`.
    pub async fn create(
        pool: &SqlitePool,
        params: NewNode,
    ) -> Result<Node, ValidationErrors> {
        let now = chrono::Utc::now().naive_utc();

        // Auto-generate slug from title when slug is blank/absent
        // (mirrors Rails' before_validation callback)
        let slug = match &params.slug {
            Some(s) if !s.is_empty() => s.clone(),
            _ => generate_slug(&params.title),
        };

        let errors = validate_node(pool, &params.title, &slug, None).await;
        if !errors.is_empty() {
            return Err(errors);
        }

        // Set published_at when creating as published (false -> true transition)
        let published_at = if params.published { Some(now) } else { None };

        let id = sqlx::query_scalar::<_, i64>(
            "INSERT INTO nodes (title, slug, body, published, published_at, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?)
             RETURNING id",
        )
        .bind(&params.title)
        .bind(&slug)
        .bind(&params.body)
        .bind(params.published)
        .bind(published_at)
        .bind(now)
        .bind(now)
        .fetch_one(pool)
        .await
        .map_err(|e| {
            // Database-level constraint violation (e.g. unique index race condition)
            let mut errors = ValidationErrors::default();
            errors.add("base", &format!("database error: {e}"));
            errors
        })?;

        // Return the freshly-inserted row
        Node::find(pool, id)
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
            })
    }

    /// Update an existing node. Applies slug auto-generation and published_at
    /// logic, then validates. Returns the updated `Node` or `ValidationErrors`.
    pub async fn update(
        &self,
        pool: &SqlitePool,
        params: UpdateNode,
    ) -> Result<Node, ValidationErrors> {
        let now = chrono::Utc::now().naive_utc();

        // Auto-generate slug from title when slug is blank/absent
        let slug = match &params.slug {
            Some(s) if !s.is_empty() => s.clone(),
            _ => generate_slug(&params.title),
        };

        let errors = validate_node(pool, &params.title, &slug, Some(self.id)).await;
        if !errors.is_empty() {
            return Err(errors);
        }

        // Published_at logic (mirrors Rails' before_save callback):
        // - Set published_at only when transitioning false -> true AND it's currently nil.
        // - Preserve existing published_at in all other cases.
        let published_at = if !self.published && params.published && self.published_at.is_none() {
            Some(now)
        } else {
            self.published_at
        };

        sqlx::query(
            "UPDATE nodes SET title = ?, slug = ?, body = ?, published = ?, published_at = ?, updated_at = ?
             WHERE id = ?",
        )
        .bind(&params.title)
        .bind(&slug)
        .bind(&params.body)
        .bind(params.published)
        .bind(published_at)
        .bind(now)
        .bind(self.id)
        .execute(pool)
        .await
        .map_err(|e| {
            let mut errors = ValidationErrors::default();
            errors.add("base", &format!("database error: {e}"));
            errors
        })?;

        Node::find(pool, self.id)
            .await
            .map_err(|e| {
                let mut errors = ValidationErrors::default();
                errors.add("base", &format!("failed to reload node: {e}"));
                errors
            })?
            .ok_or_else(|| {
                let mut errors = ValidationErrors::default();
                errors.add("base", "failed to reload node after update");
                errors
            })
    }

    /// Delete a node by its primary key. Returns true if a row was deleted.
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

    /// Create an in-memory SQLite database with the nodes schema applied.
    async fn test_pool() -> SqlitePool {
        let pool = SqlitePool::connect("sqlite::memory:")
            .await
            .expect("failed to create in-memory pool");

        sqlx::query(
            "CREATE TABLE nodes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                slug TEXT NOT NULL,
                body TEXT,
                published BOOLEAN NOT NULL DEFAULT 0,
                published_at DATETIME,
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

    // -- Validations ---------------------------------------------------------

    #[tokio::test]
    async fn valid_with_title_and_auto_generated_slug() {
        let pool = test_pool().await;
        let result = Node::create(
            &pool,
            NewNode {
                title: "Hello World".into(),
                ..Default::default()
            },
        )
        .await;
        assert!(result.is_ok());
        let node = result.unwrap();
        assert_eq!(node.slug, "hello-world");
    }

    #[tokio::test]
    async fn requires_a_title() {
        let pool = test_pool().await;
        let result = Node::create(
            &pool,
            NewNode {
                title: "".into(),
                ..Default::default()
            },
        )
        .await;
        assert!(result.is_err());
        let errors = result.unwrap_err();
        assert!(errors.get("title").unwrap().contains(&"can't be blank".to_string()));
    }

    #[tokio::test]
    async fn enforces_max_title_length() {
        let pool = test_pool().await;
        let result = Node::create(
            &pool,
            NewNode {
                title: "a".repeat(256),
                ..Default::default()
            },
        )
        .await;
        assert!(result.is_err());
        let errors = result.unwrap_err();
        assert!(errors
            .get("title")
            .unwrap()
            .contains(&"is too long (maximum is 255 characters)".to_string()));
    }

    #[tokio::test]
    async fn accepts_title_of_exactly_255_chars() {
        let pool = test_pool().await;
        let result = Node::create(
            &pool,
            NewNode {
                title: "a".repeat(255),
                ..Default::default()
            },
        )
        .await;
        assert!(result.is_ok());
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
            let result = Node::create(
                &pool,
                NewNode {
                    title: "Something".into(),
                    slug: Some(bad_slug.to_string()),
                    ..Default::default()
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
        for (i, good_slug) in valid_slugs.iter().enumerate() {
            let result = Node::create(
                &pool,
                NewNode {
                    // Unique title per iteration to avoid slug conflicts
                    title: format!("Title {i}"),
                    slug: Some(good_slug.to_string()),
                    ..Default::default()
                },
            )
            .await;
            assert!(result.is_ok(), "Expected slug '{good_slug}' to be valid");
        }
    }

    #[tokio::test]
    async fn enforces_slug_uniqueness() {
        let pool = test_pool().await;
        Node::create(
            &pool,
            NewNode {
                title: "First".into(),
                slug: Some("my-slug".into()),
                ..Default::default()
            },
        )
        .await
        .unwrap();

        let result = Node::create(
            &pool,
            NewNode {
                title: "Second".into(),
                slug: Some("my-slug".into()),
                ..Default::default()
            },
        )
        .await;
        assert!(result.is_err());
        let errors = result.unwrap_err();
        assert!(errors
            .get("slug")
            .unwrap()
            .contains(&"has already been taken".to_string()));
    }

    #[tokio::test]
    async fn enforces_max_slug_length() {
        let pool = test_pool().await;
        let result = Node::create(
            &pool,
            NewNode {
                title: "Something".into(),
                slug: Some("a".repeat(256)),
                ..Default::default()
            },
        )
        .await;
        assert!(result.is_err());
        let errors = result.unwrap_err();
        assert!(errors
            .get("slug")
            .unwrap()
            .contains(&"is too long (maximum is 255 characters)".to_string()));
    }

    #[tokio::test]
    async fn preserves_explicit_slug() {
        let pool = test_pool().await;
        let node = Node::create(
            &pool,
            NewNode {
                title: "My Title".into(),
                slug: Some("custom-slug".into()),
                ..Default::default()
            },
        )
        .await
        .unwrap();
        assert_eq!(node.slug, "custom-slug");
    }

    #[tokio::test]
    async fn fails_when_title_produces_empty_slug() {
        let pool = test_pool().await;
        let result = Node::create(
            &pool,
            NewNode {
                title: "!!!".into(),
                ..Default::default()
            },
        )
        .await;
        assert!(result.is_err());
        let errors = result.unwrap_err();
        assert!(errors.get("slug").unwrap().contains(&"can't be blank".to_string()));
    }

    #[tokio::test]
    async fn does_not_overwrite_existing_slug() {
        let pool = test_pool().await;
        let node = Node::create(
            &pool,
            NewNode {
                title: "New Title".into(),
                slug: Some("keep-this".into()),
                ..Default::default()
            },
        )
        .await
        .unwrap();
        assert_eq!(node.slug, "keep-this");
    }

    // -- Published timestamp behaviour ---------------------------------------

    #[tokio::test]
    async fn sets_published_at_when_publishing() {
        let pool = test_pool().await;
        let node = Node::create(
            &pool,
            NewNode {
                title: "Test".into(),
                ..Default::default()
            },
        )
        .await
        .unwrap();
        assert!(node.published_at.is_none());

        let updated = node
            .update(
                &pool,
                UpdateNode {
                    title: "Test".into(),
                    slug: Some("test".into()),
                    body: None,
                    published: true,
                },
            )
            .await
            .unwrap();
        assert!(updated.published_at.is_some());
    }

    #[tokio::test]
    async fn preserves_published_at_when_unpublishing() {
        let pool = test_pool().await;
        let node = Node::create(
            &pool,
            NewNode {
                title: "Test".into(),
                published: true,
                ..Default::default()
            },
        )
        .await
        .unwrap();
        let original_time = node.published_at;
        assert!(original_time.is_some());

        let updated = node
            .update(
                &pool,
                UpdateNode {
                    title: "Test".into(),
                    slug: Some("test".into()),
                    body: None,
                    published: false,
                },
            )
            .await
            .unwrap();
        assert_eq!(updated.published_at, original_time);
    }

    #[tokio::test]
    async fn does_not_set_published_at_when_stays_false() {
        let pool = test_pool().await;
        let node = Node::create(
            &pool,
            NewNode {
                title: "Test".into(),
                ..Default::default()
            },
        )
        .await
        .unwrap();

        let updated = node
            .update(
                &pool,
                UpdateNode {
                    title: "Updated Title".into(),
                    slug: None,
                    body: None,
                    published: false,
                },
            )
            .await
            .unwrap();
        assert!(updated.published_at.is_none());
    }

    #[tokio::test]
    async fn auto_manages_timestamps() {
        let pool = test_pool().await;
        let node = Node::create(
            &pool,
            NewNode {
                title: "Test".into(),
                ..Default::default()
            },
        )
        .await
        .unwrap();
        // created_at and updated_at should both be populated
        assert!(node.created_at.and_utc().timestamp() > 0);
        assert!(node.updated_at.and_utc().timestamp() > 0);
    }

    // -- Delete --------------------------------------------------------------

    #[tokio::test]
    async fn deletes_a_node() {
        let pool = test_pool().await;
        let node = Node::create(
            &pool,
            NewNode {
                title: "Doomed".into(),
                ..Default::default()
            },
        )
        .await
        .unwrap();

        let deleted = Node::delete(&pool, node.id).await.unwrap();
        assert!(deleted);

        let found = Node::find(&pool, node.id).await.unwrap();
        assert!(found.is_none());
    }

    #[tokio::test]
    async fn delete_returns_false_for_missing_node() {
        let pool = test_pool().await;
        let deleted = Node::delete(&pool, 999).await.unwrap();
        assert!(!deleted);
    }
}
