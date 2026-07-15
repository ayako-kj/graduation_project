class AddSuppressAllErrorsToShiftGroups < ActiveRecord::Migration[7.2]
  def change
    add_column :shift_groups, :suppress_all_errors, :boolean, default: false, null: false
  end
end
