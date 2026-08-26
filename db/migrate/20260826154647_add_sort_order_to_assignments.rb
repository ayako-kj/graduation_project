class AddSortOrderToAssignments < ActiveRecord::Migration[8.1]
  def up
    add_column :assignments, :sort_order, :integer

    Assignment.reset_column_information
    Assignment.order(:id).each_with_index do |assignment, index|
      assignment.update_column(:sort_order, index + 1)
    end
  end

  def down
    remove_column :assignments, :sort_order
  end
end
