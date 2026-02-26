class AddVersioning < ActiveRecord::Migration[8.1]
  def up
    create_table :branches do |t|
      t.string :name, null: false
      t.timestamps
    end

    add_index :branches, :name, unique: true

    execute <<-SQL
      INSERT INTO branches (name, created_at, updated_at)
      VALUES ('main', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
             ('published', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    SQL

    create_table :versions do |t|
      t.references :node, null: false, foreign_key: { on_delete: :cascade }
      t.references :branch, null: false, foreign_key: { on_delete: :restrict }
      t.references :parent_version, null: true, foreign_key: { to_table: :versions, on_delete: :nullify }
      t.references :source_version, null: true, foreign_key: { to_table: :versions, on_delete: :nullify }
      t.string :title, null: false
      t.text :body
      t.text :commit_message
      t.datetime :committed_at
      t.timestamps
    end

    add_index :versions, [:node_id, :branch_id],
              unique: true,
              where: "committed_at IS NULL",
              name: "index_versions_uncommitted_unique"

    add_index :versions, [:node_id, :branch_id, :committed_at],
              name: "index_versions_on_node_branch_committed"

    # Migrate existing node data into versions
    main_branch_id = execute("SELECT id FROM branches WHERE name = 'main' LIMIT 1").first["id"]
    published_branch_id = execute("SELECT id FROM branches WHERE name = 'published' LIMIT 1").first["id"]

    nodes = execute("SELECT id, title, body, published, published_at, updated_at FROM nodes")
    nodes.each do |node|
      # Create committed version on main branch
      execute <<-SQL
        INSERT INTO versions (node_id, branch_id, title, body, commit_message, committed_at, created_at, updated_at)
        VALUES (#{node['id']}, #{main_branch_id}, #{quote(node['title'])}, #{quote(node['body'])}, 'Migrated from legacy schema', #{quote(node['updated_at'])}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      SQL

      if node["published"] == 1 || node["published"] == true || node["published"] == "t"
        main_version_id = execute("SELECT id FROM versions WHERE node_id = #{node['id']} AND branch_id = #{main_branch_id} ORDER BY id DESC LIMIT 1").first["id"]
        committed_at = node["published_at"] || node["updated_at"]

        execute <<-SQL
          INSERT INTO versions (node_id, branch_id, source_version_id, title, body, commit_message, committed_at, created_at, updated_at)
          VALUES (#{node['id']}, #{published_branch_id}, #{main_version_id}, #{quote(node['title'])}, #{quote(node['body'])}, 'Migrated from legacy schema', #{quote(committed_at)}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        SQL
      end
    end

    remove_column :nodes, :title
    remove_column :nodes, :body
    remove_column :nodes, :published
    remove_column :nodes, :published_at
  end

  def down
    add_column :nodes, :title, :string
    add_column :nodes, :body, :text
    add_column :nodes, :published, :boolean, default: false, null: false
    add_column :nodes, :published_at, :datetime

    main_branch_id = execute("SELECT id FROM branches WHERE name = 'main' LIMIT 1").first["id"]
    published_branch_id = execute("SELECT id FROM branches WHERE name = 'published' LIMIT 1").first["id"]

    nodes = execute("SELECT id FROM nodes")
    nodes.each do |node|
      # Get latest version on main (prefer committed, fall back to uncommitted)
      main_version = execute(<<-SQL).first
        SELECT title, body FROM versions
        WHERE node_id = #{node['id']} AND branch_id = #{main_branch_id}
        ORDER BY committed_at DESC NULLS LAST LIMIT 1
      SQL

      # Fall back to any version for this node
      main_version ||= execute(<<-SQL).first
        SELECT title, body FROM versions
        WHERE node_id = #{node['id']}
        ORDER BY committed_at DESC NULLS LAST LIMIT 1
      SQL

      if main_version
        execute <<-SQL
          UPDATE nodes SET title = #{quote(main_version['title'])}, body = #{quote(main_version['body'])} WHERE id = #{node['id']}
        SQL
      end

      # Check if published
      published_version = execute(<<-SQL).first
        SELECT committed_at FROM versions
        WHERE node_id = #{node['id']} AND branch_id = #{published_branch_id} AND committed_at IS NOT NULL
        ORDER BY committed_at DESC LIMIT 1
      SQL

      if published_version
        execute <<-SQL
          UPDATE nodes SET published = 1, published_at = #{quote(published_version['committed_at'])} WHERE id = #{node['id']}
        SQL
      end
    end

    # Enforce NOT NULL on title after populating (default for any remaining NULLs)
    change_column_null :nodes, :title, false, "Untitled"

    drop_table :versions
    drop_table :branches
  end

  private

  def quote(value)
    ActiveRecord::Base.connection.quote(value)
  end
end
