class AddUnavailableWdaysToStaffs < ActiveRecord::Migration[7.2]
  def change
    add_column :staffs, :unavailable_wdays, :string, default: "[]", null: false
  end
end
