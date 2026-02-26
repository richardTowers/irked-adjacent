-- VERS-01: Add branches and versions tables, slim down nodes.
-- Mirrors the Rails migration: 20260226124543_add_versioning.rb

-- Enable foreign key enforcement (required for SQLite)
PRAGMA foreign_keys = ON;

-- 1. Create the branches table
CREATE TABLE branches (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL
);

CREATE UNIQUE INDEX index_branches_on_name ON branches (name);

-- Seed the two protected branches
INSERT INTO branches (name, created_at, updated_at)
VALUES ('main', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
       ('published', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

-- 2. Create the versions table
CREATE TABLE versions (
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
);

CREATE INDEX index_versions_on_node_id ON versions (node_id);
CREATE INDEX index_versions_on_branch_id ON versions (branch_id);
CREATE INDEX index_versions_on_parent_version_id ON versions (parent_version_id);
CREATE INDEX index_versions_on_source_version_id ON versions (source_version_id);

-- Partial unique index: at most one uncommitted version per (node, branch)
CREATE UNIQUE INDEX index_versions_uncommitted_unique
    ON versions (node_id, branch_id) WHERE committed_at IS NULL;

-- Composite index for efficient current-version resolution
CREATE INDEX index_versions_on_node_branch_committed
    ON versions (node_id, branch_id, committed_at);

-- 3. Migrate existing node data into versions
-- Each existing node gets a committed version on main.
-- Published nodes also get a committed version on the published branch.

-- Create committed versions on main for all nodes
INSERT INTO versions (node_id, branch_id, title, body, commit_message, committed_at, created_at, updated_at)
SELECT
    n.id,
    (SELECT id FROM branches WHERE name = 'main'),
    n.title,
    n.body,
    'Migrated from legacy schema',
    n.updated_at,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
FROM nodes n;

-- Create committed versions on published for published nodes
INSERT INTO versions (node_id, branch_id, source_version_id, title, body, commit_message, committed_at, created_at, updated_at)
SELECT
    n.id,
    (SELECT id FROM branches WHERE name = 'published'),
    v.id,
    n.title,
    n.body,
    'Migrated from legacy schema',
    COALESCE(n.published_at, n.updated_at),
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
FROM nodes n
JOIN versions v ON v.node_id = n.id AND v.branch_id = (SELECT id FROM branches WHERE name = 'main')
WHERE n.published = 1;

-- 4. Remove content columns from nodes.
-- SQLite doesn't support DROP COLUMN in older versions, so we recreate the table.
-- sqlx migrations run on modern SQLite (3.35+) which supports ALTER TABLE DROP COLUMN.
ALTER TABLE nodes DROP COLUMN title;
ALTER TABLE nodes DROP COLUMN body;
ALTER TABLE nodes DROP COLUMN published;
ALTER TABLE nodes DROP COLUMN published_at;
