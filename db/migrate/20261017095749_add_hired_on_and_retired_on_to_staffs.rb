class AddHiredOnAndRetiredOnToStaffs < ActiveRecord::Migration[8.1]
  def change
    add_column :staffs, :hired_on, :date
    add_column :staffs, :retired_on, :date
  end
end
