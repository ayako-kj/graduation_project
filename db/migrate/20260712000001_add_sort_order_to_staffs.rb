class AddSortOrderToStaffs < ActiveRecord::Migration[7.2]
  def up
    add_column :staffs, :sort_order, :integer

    Staff.reset_column_information
    Staff.order(:id).each_with_index do |staff, index|
      staff.update_column(:sort_order, index + 1)
    end
  end

  def down
    remove_column :staffs, :sort_order
  end
end
