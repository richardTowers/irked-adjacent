class AddContentTypeAndFieldsToNodes < ActiveRecord::Migration[8.1]
  def up
    # Step 1: Add new columns (content_type_id nullable initially)
    add_column :nodes, :content_type_id, :integer
    add_column :nodes, :fields, :json, null: false, default: {}

    # Step 2: For each team that has nodes, create a "Page" content type
    # with a single "body" text field definition
    teams_with_nodes = execute("SELECT DISTINCT team_id FROM nodes WHERE team_id IS NOT NULL").map { |row| row["team_id"] }

    teams_with_nodes.each do |team_id|
      # Create the Page content type
      execute <<~SQL
        INSERT INTO content_types (name, slug, description, team_id, created_at, updated_at)
        VALUES ('Page', 'page-#{team_id}', 'Default page content type (migrated from body column)', #{team_id}, datetime('now'), datetime('now'))
      SQL

      content_type_id = execute("SELECT last_insert_rowid() AS id").first["id"]

      # Create the body field definition
      execute <<~SQL
        INSERT INTO field_definitions (content_type_id, name, api_key, field_type, required, position, created_at, updated_at)
        VALUES (#{content_type_id}, 'Body', 'body', 'text', 0, 0, datetime('now'), datetime('now'))
      SQL

      # Step 3: Migrate node body data into fields JSON
      # Nodes with a body value
      execute <<~SQL
        UPDATE nodes
        SET content_type_id = #{content_type_id},
            fields = json_object('body', body)
        WHERE team_id = #{team_id} AND body IS NOT NULL AND body != ''
      SQL

      # Nodes without a body value
      execute <<~SQL
        UPDATE nodes
        SET content_type_id = #{content_type_id},
            fields = '{}'
        WHERE team_id = #{team_id} AND (body IS NULL OR body = '')
      SQL
    end

    # Handle orphan nodes (no team_id) — skip them, they already violate constraints
    # and cannot be assigned a content type without a team.

    # Step 4: Make content_type_id NOT NULL
    change_column_null :nodes, :content_type_id, false

    # Step 5: Add foreign key and index
    add_index :nodes, :content_type_id
    add_foreign_key :nodes, :content_types

    # Step 6: Remove the body column
    remove_column :nodes, :body
  end

  def down
    add_column :nodes, :body, :text

    # Attempt to restore body from fields JSON
    execute <<~SQL
      UPDATE nodes
      SET body = json_extract(fields, '$.body')
      WHERE json_extract(fields, '$.body') IS NOT NULL
    SQL

    remove_foreign_key :nodes, :content_types
    remove_index :nodes, :content_type_id
    remove_column :nodes, :content_type_id
    remove_column :nodes, :fields
  end
end
