CREATE TABLE nodes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    slug TEXT NOT NULL,
    body TEXT,
    published BOOLEAN NOT NULL DEFAULT 0,
    published_at DATETIME,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL
);

CREATE UNIQUE INDEX index_nodes_on_slug ON nodes (slug);
