class AddDutyCountsToWorkdayManualEntries < ActiveRecord::Migration[7.2]
  def change
    add_column :workday_manual_entries, :early_count, :integer
    add_column :workday_manual_entries, :post_duty_count, :integer
    add_column :workday_manual_entries, :holiday_post_duty_count, :integer
  end
end
