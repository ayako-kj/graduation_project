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

ActiveRecord::Schema[7.2].define(version: 2026_07_09_175405) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "admins", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admins_on_email", unique: true
    t.index ["reset_password_token"], name: "index_admins_on_reset_password_token", unique: true
  end

  create_table "employment_types", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "leave_requests", force: :cascade do |t|
    t.bigint "staff_id", null: false
    t.date "date"
    t.string "reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["staff_id"], name: "index_leave_requests_on_staff_id"
  end

  create_table "placement_rules", force: :cascade do |t|
    t.bigint "staff_type_id", null: false
    t.integer "min_count"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["staff_type_id"], name: "index_placement_rules_on_staff_type_id"
  end

  create_table "shift_groups", force: :cascade do |t|
    t.date "target_month"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "shifts", force: :cascade do |t|
    t.bigint "shift_group_id", null: false
    t.bigint "staff_id", null: false
    t.date "date"
    t.boolean "is_working"
    t.text "validation_errors"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "is_early", default: false, null: false
    t.boolean "is_post_duty", default: false, null: false
    t.boolean "is_holiday_post_duty", default: false, null: false
    t.index ["shift_group_id"], name: "index_shifts_on_shift_group_id"
    t.index ["staff_id"], name: "index_shifts_on_staff_id"
  end

  create_table "special_date_staffs", force: :cascade do |t|
    t.bigint "special_date_id", null: false
    t.bigint "staff_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["special_date_id"], name: "index_special_date_staffs_on_special_date_id"
    t.index ["staff_id"], name: "index_special_date_staffs_on_staff_id"
  end

  create_table "special_dates", force: :cascade do |t|
    t.date "date"
    t.string "label"
    t.string "target_group"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "staff_types", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "staffs", force: :cascade do |t|
    t.string "name"
    t.bigint "staff_type_id", null: false
    t.bigint "employment_type_id", null: false
    t.integer "weekly_work_days"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employment_type_id"], name: "index_staffs_on_employment_type_id"
    t.index ["staff_type_id"], name: "index_staffs_on_staff_type_id"
  end

  create_table "workday_manual_entries", force: :cascade do |t|
    t.bigint "staff_id", null: false
    t.date "year_month", null: false
    t.integer "working_days", default: 0, null: false
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["staff_id", "year_month"], name: "index_workday_manual_entries_on_staff_id_and_year_month", unique: true
    t.index ["staff_id"], name: "index_workday_manual_entries_on_staff_id"
  end

  add_foreign_key "leave_requests", "staffs"
  add_foreign_key "placement_rules", "staff_types"
  add_foreign_key "shifts", "shift_groups"
  add_foreign_key "shifts", "staffs"
  add_foreign_key "special_date_staffs", "special_dates"
  add_foreign_key "special_date_staffs", "staffs"
  add_foreign_key "staffs", "employment_types"
  add_foreign_key "staffs", "staff_types"
  add_foreign_key "workday_manual_entries", "staffs"
end
