class AddTimeRangeToSpecialDates < ActiveRecord::Migration[8.1]
  def change
    add_column :special_dates, :start_time, :time
    add_column :special_dates, :end_time, :time
  end
end
