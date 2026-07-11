class AddSortOrderToStaffTypes < ActiveRecord::Migration[7.2]
  DESIRED_ORDER = %w[館長 副館長 司書 行政職 一般事務 専門司書].freeze

  def up
    add_column :staff_types, :sort_order, :integer

    DESIRED_ORDER.each_with_index do |name, index|
      StaffType.where(name: name).update_all(sort_order: index + 1)
    end

    StaffType.where(sort_order: nil).each_with_index do |st, index|
      st.update_column(:sort_order, DESIRED_ORDER.size + index + 1)
    end
  end

  def down
    remove_column :staff_types, :sort_order
  end
end
