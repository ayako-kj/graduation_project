class CreateAssignments < ActiveRecord::Migration[7.2]
  def change
    create_table :assignments do |t|
      t.string :name, null: false
      t.integer :meeting_wday
      t.references :library, null: false, foreign_key: true
      t.timestamps
    end

    create_table :staff_assignments do |t|
      t.references :staff, null: false, foreign_key: true
      t.references :assignment, null: false, foreign_key: true
      t.timestamps
    end

    add_index :staff_assignments, [:staff_id, :assignment_id], unique: true
  end
end
