class AddCreatedByStaffIdToSpecialDates < ActiveRecord::Migration[7.2]
  def change
    add_column :special_dates, :created_by_staff_id, :integer
  end
end
