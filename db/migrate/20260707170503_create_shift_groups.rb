class CreateShiftGroups < ActiveRecord::Migration[7.2]
  def change
    create_table :shift_groups do |t|
      t.date :target_month
      t.string :status

      t.timestamps
    end
  end
end
