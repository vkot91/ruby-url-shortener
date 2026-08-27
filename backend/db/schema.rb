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

ActiveRecord::Schema[8.0].define(version: 2026_08_27_090600) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "accounts", force: :cascade do |t|
    t.citext "email", null: false
    t.text "password_digest", null: false
    t.text "role", default: "creator", null: false
    t.text "plan", default: "free", null: false
    t.datetime "banned_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_accounts_on_email", unique: true
    t.check_constraint "plan = 'free'::text", name: "accounts_plan_check"
    t.check_constraint "role = ANY (ARRAY['creator'::text, 'admin'::text])", name: "accounts_role_check"
  end

  create_table "blocked_domains", force: :cascade do |t|
    t.citext "domain", null: false
    t.text "reason"
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.index ["created_by_id"], name: "index_blocked_domains_on_created_by_id"
    t.index ["domain"], name: "index_blocked_domains_on_domain", unique: true
  end

  create_table "clicks", force: :cascade do |t|
    t.bigint "link_id", null: false
    t.datetime "occurred_at", null: false
    t.index ["link_id", "occurred_at"], name: "index_clicks_on_link_id_and_occurred_at", order: { occurred_at: :desc }
  end

  create_table "links", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.text "code", null: false
    t.text "destination_url", null: false
    t.text "name"
    t.bigint "clicks_count", default: 0, null: false
    t.datetime "banned_at"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"], name: "index_links_on_account_id_and_created_at_active", order: { created_at: :desc }, where: "(deleted_at IS NULL)"
    t.index ["account_id"], name: "index_links_on_account_id"
    t.index ["code"], name: "index_links_on_code", unique: true
    t.index ["destination_url"], name: "index_links_on_destination_url_trgm", opclass: :gin_trgm_ops, using: :gin
    t.check_constraint "length(code) >= 3 AND length(code) <= 32", name: "links_code_length_check"
  end

  create_table "refresh_tokens", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.text "token_digest", null: false
    t.uuid "family_id", null: false
    t.datetime "used_at"
    t.datetime "expires_at", null: false
    t.datetime "revoked_at"
    t.text "user_agent"
    t.text "ip_address"
    t.datetime "created_at", null: false
    t.index ["account_id"], name: "index_refresh_tokens_on_account_id"
    t.index ["family_id"], name: "index_refresh_tokens_on_family_id"
    t.index ["token_digest"], name: "index_refresh_tokens_on_token_digest", unique: true
  end

  create_table "reports", force: :cascade do |t|
    t.bigint "link_id", null: false
    t.text "reason"
    t.text "status", default: "pending", null: false
    t.bigint "reviewed_by_id"
    t.datetime "reviewed_at"
    t.datetime "created_at", null: false
    t.index ["link_id"], name: "index_reports_on_link_id"
    t.index ["reviewed_by_id"], name: "index_reports_on_reviewed_by_id"
    t.index ["status", "created_at"], name: "index_reports_on_status_and_created_at"
    t.check_constraint "status = ANY (ARRAY['pending'::text, 'actioned'::text, 'dismissed'::text])", name: "reports_status_check"
  end

  add_foreign_key "blocked_domains", "accounts", column: "created_by_id"
  add_foreign_key "clicks", "links"
  add_foreign_key "links", "accounts"
  add_foreign_key "refresh_tokens", "accounts", on_delete: :cascade
  add_foreign_key "reports", "accounts", column: "reviewed_by_id"
  add_foreign_key "reports", "links"
end
