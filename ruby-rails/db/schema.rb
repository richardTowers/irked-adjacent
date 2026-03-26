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

ActiveRecord::Schema[8.1].define(version: 2026_03_26_130000) do
  create_table "content_types", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.string "slug", null: false
    t.integer "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_content_types_on_slug", unique: true
    t.index ["team_id"], name: "index_content_types_on_team_id"
  end

  create_table "field_definitions", force: :cascade do |t|
    t.string "api_key", null: false
    t.integer "content_type_id", null: false
    t.datetime "created_at", null: false
    t.string "field_type", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.boolean "required", default: false, null: false
    t.datetime "updated_at", null: false
    t.json "validations"
    t.index ["content_type_id", "api_key"], name: "index_field_definitions_on_content_type_id_and_api_key", unique: true
    t.index ["content_type_id"], name: "index_field_definitions_on_content_type_id"
  end

  create_table "memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "role", default: "member", null: false
    t.integer "team_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["team_id"], name: "index_memberships_on_team_id"
    t.index ["user_id", "team_id"], name: "index_memberships_on_user_id_and_team_id", unique: true
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "nodes", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.boolean "published", default: false, null: false
    t.datetime "published_at"
    t.string "slug", null: false
    t.integer "team_id"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_nodes_on_slug", unique: true
    t.index ["team_id"], name: "index_nodes_on_team_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "teams", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_teams_on_slug", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "content_types", "teams"
  add_foreign_key "field_definitions", "content_types"
  add_foreign_key "memberships", "teams"
  add_foreign_key "memberships", "users"
  add_foreign_key "nodes", "teams"
  add_foreign_key "sessions", "users"
end
