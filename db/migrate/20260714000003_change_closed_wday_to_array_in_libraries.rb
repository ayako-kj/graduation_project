class ChangeClosedWdayToArrayInLibraries < ActiveRecord::Migration[7.2]
  def up
    add_column :libraries, :closed_wdays, :string, default: "[]", null: false

    Library.find_each do |lib|
      wdays = lib.regular_closed_wday.present? ? [lib.regular_closed_wday] : []
      lib.update_column(:closed_wdays, wdays.to_json)
    end

    remove_column :libraries, :regular_closed_wday
  end

  def down
    add_column :libraries, :regular_closed_wday, :integer, default: 2
    remove_column :libraries, :closed_wdays
  end
end
