# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_02_26_124543) do
  create_table "branches", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_branches_on_name", unique: true
  end

  create_table "nodes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_nodes_on_slug", unique: true
  end

  create_table "versions", force: :cascade do |t|
    t.text "body"
    t.integer "branch_id", null: false
    t.text "commit_message"
    t.datetime "committed_at"
    t.datetime "created_at", null: false
    t.integer "node_id", null: false
    t.integer "parent_version_id"
    t.integer "source_version_id"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["branch_id"], name: "index_versions_on_branch_id"
    t.index ["node_id", "branch_id", "committed_at"], name: "index_versions_on_node_branch_committed"
    t.index ["node_id", "branch_id"], name: "index_versions_uncommitted_unique", unique: true, where: "committed_at IS NULL"
    t.index ["node_id"], name: "index_versions_on_node_id"
    t.index ["parent_version_id"], name: "index_versions_on_parent_version_id"
    t.index ["source_version_id"], name: "index_versions_on_source_version_id"
  end

  add_foreign_key "versions", "branches", on_delete: :restrict
  add_foreign_key "versions", "nodes", on_delete: :cascade
  add_foreign_key "versions", "versions", column: "parent_version_id", on_delete: :nullify
  add_foreign_key "versions", "versions", column: "source_version_id", on_delete: :nullify
end
