class CreateActualLeaves < ActiveRecord::Migration[7.2]
  def change
    create_table :actual_leaves do |t|
      t.references :staff, null: false, foreign_key: true
      t.date :date, null: false
      t.string :leave_type, null: false, default: "annual"

      t.timestamps
    end

    add_index :actual_leaves, [:staff_id, :date], unique: true
  end
end
