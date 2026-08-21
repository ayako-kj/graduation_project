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

ActiveRecord::Schema[8.1].define(version: 2026_08_21_075504) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "actual_leaves", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.string "leave_type", default: "annual", null: false
    t.bigint "staff_id", null: false
    t.datetime "updated_at", null: false
    t.index ["staff_id", "date"], name: "index_actual_leaves_on_staff_id_and_date", unique: true
    t.index ["staff_id"], name: "index_actual_leaves_on_staff_id"
  end

  create_table "admins", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.bigint "library_id"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admins_on_email", unique: true
    t.index ["library_id"], name: "index_admins_on_library_id"
    t.index ["reset_password_token"], name: "index_admins_on_reset_password_token", unique: true
  end

  create_table "assignments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "library_id", null: false
    t.integer "meeting_wday"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["library_id"], name: "index_assignments_on_library_id"
  end

  create_table "employment_types", force: :cascade do |t|
    t.decimal "city_hall_daily_hours", precision: 4, scale: 2, default: "6.0", null: false
    t.datetime "created_at", null: false
    t.decimal "daily_work_hours", precision: 4, scale: 2, default: "7.5", null: false
    t.boolean "is_regular", default: false, null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "input_deadlines", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "deadline_on"
    t.bigint "library_id", null: false
    t.date "target_month", null: false
    t.datetime "updated_at", null: false
    t.index ["library_id", "target_month"], name: "index_input_deadlines_on_library_id_and_target_month", unique: true
    t.index ["library_id"], name: "index_input_deadlines_on_library_id"
  end

  create_table "leave_requests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date"
    t.string "note"
    t.string "reason"
    t.bigint "staff_id", null: false
    t.datetime "updated_at", null: false
    t.index ["staff_id"], name: "index_leave_requests_on_staff_id"
  end

  create_table "libraries", force: :cascade do |t|
    t.string "closed_wdays", default: "[]", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "mobile_libraries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "library_id", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["library_id"], name: "index_mobile_libraries_on_library_id"
  end

  create_table "mobile_library_exception_staffs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "mobile_library_exception_id", null: false
    t.bigint "staff_id", null: false
    t.datetime "updated_at", null: false
    t.index ["mobile_library_exception_id"], name: "idx_on_mobile_library_exception_id_ad08dacba4"
    t.index ["staff_id"], name: "index_mobile_library_exception_staffs_on_staff_id"
  end

  create_table "mobile_library_exceptions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date"
    t.bigint "mobile_library_route_id", null: false
    t.date "target_month", null: false
    t.datetime "updated_at", null: false
    t.index ["mobile_library_route_id", "target_month"], name: "index_ml_exceptions_on_route_and_month", unique: true
    t.index ["mobile_library_route_id"], name: "index_mobile_library_exceptions_on_mobile_library_route_id"
  end

  create_table "mobile_library_routes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "mobile_library_id", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.integer "wday", null: false
    t.integer "week_number", null: false
    t.index ["mobile_library_id"], name: "index_mobile_library_routes_on_mobile_library_id"
  end

  create_table "mobile_library_staff_assignments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "mobile_library_route_id", null: false
    t.bigint "staff_id", null: false
    t.datetime "updated_at", null: false
    t.index ["mobile_library_route_id"], name: "idx_on_mobile_library_route_id_e4b84dc899"
    t.index ["staff_id"], name: "index_mobile_library_staff_assignments_on_staff_id"
  end

  create_table "monthly_submissions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "leave_submitted_at"
    t.datetime "schedule_submitted_at"
    t.bigint "staff_id", null: false
    t.date "target_month", null: false
    t.datetime "updated_at", null: false
    t.index ["staff_id", "target_month"], name: "index_monthly_submissions_on_staff_id_and_target_month", unique: true
    t.index ["staff_id"], name: "index_monthly_submissions_on_staff_id"
  end

  create_table "placement_rules", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "employment_type_id"
    t.bigint "library_id"
    t.integer "min_count"
    t.string "rule_type", default: "min_count", null: false
    t.bigint "staff_type_id"
    t.text "staff_type_ids"
    t.datetime "updated_at", null: false
    t.index ["library_id"], name: "index_placement_rules_on_library_id"
    t.index ["staff_type_id"], name: "index_placement_rules_on_staff_type_id"
  end

  create_table "shift_groups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "library_id"
    t.string "status"
    t.boolean "suppress_all_errors", default: false, null: false
    t.date "target_month"
    t.datetime "updated_at", null: false
    t.index ["library_id"], name: "index_shift_groups_on_library_id"
  end

  create_table "shift_snapshots", force: :cascade do |t|
    t.datetime "confirmed_at", null: false
    t.datetime "created_at", null: false
    t.bigint "library_id", null: false
    t.text "snapshot_data", null: false
    t.date "target_month", null: false
    t.datetime "updated_at", null: false
    t.index ["library_id", "target_month"], name: "index_shift_snapshots_on_library_id_and_target_month", unique: true
    t.index ["library_id"], name: "index_shift_snapshots_on_library_id"
  end

  create_table "shifts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date"
    t.boolean "is_early", default: false, null: false
    t.boolean "is_holiday_post_duty", default: false, null: false
    t.boolean "is_post_duty", default: false, null: false
    t.boolean "is_working"
    t.bigint "shift_group_id", null: false
    t.bigint "staff_id", null: false
    t.datetime "updated_at", null: false
    t.text "validation_errors"
    t.index ["shift_group_id"], name: "index_shifts_on_shift_group_id"
    t.index ["staff_id"], name: "index_shifts_on_staff_id"
  end

  create_table "special_date_staffs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "special_date_id", null: false
    t.bigint "staff_id", null: false
    t.datetime "updated_at", null: false
    t.index ["special_date_id"], name: "index_special_date_staffs_on_special_date_id"
    t.index ["staff_id"], name: "index_special_date_staffs_on_staff_id"
  end

  create_table "special_dates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "created_by_staff_id"
    t.date "date"
    t.time "end_time"
    t.string "label"
    t.bigint "library_id"
    t.time "start_time"
    t.string "target_group"
    t.datetime "updated_at", null: false
    t.index ["library_id"], name: "index_special_dates_on_library_id"
  end

  create_table "staff_assignments", force: :cascade do |t|
    t.bigint "assignment_id", null: false
    t.datetime "created_at", null: false
    t.bigint "staff_id", null: false
    t.datetime "updated_at", null: false
    t.index ["assignment_id"], name: "index_staff_assignments_on_assignment_id"
    t.index ["staff_id", "assignment_id"], name: "index_staff_assignments_on_staff_id_and_assignment_id", unique: true
    t.index ["staff_id"], name: "index_staff_assignments_on_staff_id"
  end

  create_table "staff_types", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.integer "sort_order"
    t.datetime "updated_at", null: false
  end

  create_table "staffs", force: :cascade do |t|
    t.string "access_token"
    t.datetime "created_at", null: false
    t.decimal "daily_work_hours", precision: 4, scale: 2
    t.bigint "employment_type_id", null: false
    t.bigint "library_id"
    t.string "name"
    t.integer "sort_order"
    t.bigint "staff_type_id", null: false
    t.string "unavailable_wdays", default: "[]", null: false
    t.datetime "updated_at", null: false
    t.integer "weekly_work_days"
    t.index ["access_token"], name: "index_staffs_on_access_token", unique: true
    t.index ["employment_type_id"], name: "index_staffs_on_employment_type_id"
    t.index ["library_id"], name: "index_staffs_on_library_id"
    t.index ["staff_type_id"], name: "index_staffs_on_staff_type_id"
  end

  create_table "temporary_closed_dates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.string "label"
    t.bigint "library_id", null: false
    t.datetime "updated_at", null: false
    t.index ["library_id", "date"], name: "index_temporary_closed_dates_on_library_id_and_date", unique: true
    t.index ["library_id"], name: "index_temporary_closed_dates_on_library_id"
  end

  create_table "temporary_open_dates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.string "label"
    t.bigint "library_id", null: false
    t.datetime "updated_at", null: false
    t.index ["library_id", "date"], name: "index_temporary_open_dates_on_library_id_and_date", unique: true
    t.index ["library_id"], name: "index_temporary_open_dates_on_library_id"
  end

  create_table "workday_manual_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "early_count"
    t.integer "holiday_post_duty_count"
    t.text "note"
    t.integer "post_duty_count"
    t.bigint "staff_id", null: false
    t.datetime "updated_at", null: false
    t.integer "weekend_consecutive_off_count"
    t.integer "weekend_consecutive_work_count"
    t.integer "working_days", default: 0, null: false
    t.date "year_month", null: false
    t.index ["staff_id", "year_month"], name: "index_workday_manual_entries_on_staff_id_and_year_month", unique: true
    t.index ["staff_id"], name: "index_workday_manual_entries_on_staff_id"
  end

  add_foreign_key "actual_leaves", "staffs"
  add_foreign_key "admins", "libraries"
  add_foreign_key "assignments", "libraries"
  add_foreign_key "input_deadlines", "libraries"
  add_foreign_key "leave_requests", "staffs"
  add_foreign_key "mobile_libraries", "libraries"
  add_foreign_key "mobile_library_exception_staffs", "mobile_library_exceptions"
  add_foreign_key "mobile_library_exception_staffs", "staffs"
  add_foreign_key "mobile_library_exceptions", "mobile_library_routes"
  add_foreign_key "mobile_library_routes", "mobile_libraries"
  add_foreign_key "mobile_library_staff_assignments", "mobile_library_routes"
  add_foreign_key "mobile_library_staff_assignments", "staffs"
  add_foreign_key "monthly_submissions", "staffs"
  add_foreign_key "placement_rules", "employment_types"
  add_foreign_key "placement_rules", "libraries"
  add_foreign_key "placement_rules", "staff_types"
  add_foreign_key "shift_groups", "libraries"
  add_foreign_key "shift_snapshots", "libraries"
  add_foreign_key "shifts", "shift_groups"
  add_foreign_key "shifts", "staffs"
  add_foreign_key "special_date_staffs", "special_dates"
  add_foreign_key "special_date_staffs", "staffs"
  add_foreign_key "special_dates", "libraries"
  add_foreign_key "staff_assignments", "assignments"
  add_foreign_key "staff_assignments", "staffs"
  add_foreign_key "staffs", "employment_types"
  add_foreign_key "staffs", "libraries"
  add_foreign_key "staffs", "staff_types"
  add_foreign_key "temporary_closed_dates", "libraries"
  add_foreign_key "temporary_open_dates", "libraries"
  add_foreign_key "workday_manual_entries", "staffs"
end
