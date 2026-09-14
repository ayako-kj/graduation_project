class CreateHourlyLeaves < ActiveRecord::Migration[8.1]
  def change
    create_table :hourly_leaves do |t|
      t.references :staff, null: false, foreign_key: true
      t.date :date, null: false
      t.string :time_range_label

      t.timestamps
    end
    add_index :hourly_leaves, [:staff_id, :date], unique: true
  end
end
