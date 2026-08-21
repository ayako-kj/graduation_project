class MakeWorkingDaysNullableOnWorkdayManualEntries < ActiveRecord::Migration[8.1]
  def up
    change_column_null :workday_manual_entries, :working_days, true
    change_column_default :workday_manual_entries, :working_days, from: 0, to: nil
  end

  def down
    change_column_default :workday_manual_entries, :working_days, from: nil, to: 0
    change_column_null :workday_manual_entries, :working_days, false, 0
  end
end
