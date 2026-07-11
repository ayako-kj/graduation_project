class AddLibraryIdToTables < ActiveRecord::Migration[7.2]
  def change
    add_reference :admins, :library, foreign_key: true
    add_reference :staffs, :library, foreign_key: true
    add_reference :placement_rules, :library, foreign_key: true
    add_reference :special_dates, :library, foreign_key: true
    add_reference :shift_groups, :library, foreign_key: true
  end
end
