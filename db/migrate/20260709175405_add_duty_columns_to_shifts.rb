class AddDutyColumnsToShifts < ActiveRecord::Migration[7.2]
  def change
    add_column :shifts, :is_early, :boolean, default: false, null: false
    add_column :shifts, :is_post_duty, :boolean, default: false, null: false
    add_column :shifts, :is_holiday_post_duty, :boolean, default: false, null: false
  end
end
