class AddWeekendConsecutiveCountsToWorkdayManualEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :workday_manual_entries, :weekend_consecutive_work_count, :integer
    add_column :workday_manual_entries, :weekend_consecutive_off_count, :integer
  end
end
