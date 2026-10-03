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

ActiveRecord::Schema[8.1].define(version: 2026_10_03_090200) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.string "battle_net_id", null: false
    t.string "battletag", null: false
    t.datetime "created_at", null: false
    t.datetime "last_login_at"
    t.datetime "updated_at", null: false
    t.index ["battle_net_id"], name: "index_accounts_on_battle_net_id", unique: true
  end

  create_table "settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.string "value"
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  create_table "world_of_warcraft_accounts", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "battle_net_account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_world_of_warcraft_accounts_on_account_id"
    t.index ["battle_net_account_id"], name: "index_world_of_warcraft_accounts_on_battle_net_account_id", unique: true
  end

  create_table "world_of_warcraft_characters", force: :cascade do |t|
    t.bigint "battle_net_character_id", null: false
    t.string "character_class", null: false
    t.datetime "created_at", null: false
    t.integer "level", null: false
    t.string "name", null: false
    t.string "realm_slug", null: false
    t.datetime "updated_at", null: false
    t.bigint "world_of_warcraft_account_id", null: false
    t.bigint "world_of_warcraft_guild_rank_id"
    t.index ["battle_net_character_id"], name: "index_wow_characters_on_battle_net_character_id", unique: true
    t.index ["realm_slug", "name"], name: "index_wow_characters_on_realm_slug_and_name", unique: true
    t.index ["world_of_warcraft_account_id"], name: "index_wow_characters_on_wow_account_id"
    t.index ["world_of_warcraft_guild_rank_id"], name: "index_wow_characters_on_wow_guild_rank_id"
  end

  create_table "world_of_warcraft_guild_ranks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.boolean "officer", default: false, null: false
    t.integer "rank", null: false
    t.datetime "updated_at", null: false
    t.index ["rank"], name: "index_world_of_warcraft_guild_ranks_on_rank", unique: true
  end

  add_foreign_key "world_of_warcraft_accounts", "accounts"
  add_foreign_key "world_of_warcraft_characters", "world_of_warcraft_accounts"
  add_foreign_key "world_of_warcraft_characters", "world_of_warcraft_guild_ranks"
end
