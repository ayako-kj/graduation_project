class CreateWorkdayManualEntries < ActiveRecord::Migration[7.2]
  def change
    create_table :workday_manual_entries do |t|
      t.references :staff, null: false, foreign_key: true
      t.date :year_month, null: false
      t.integer :working_days, null: false, default: 0
      t.text :note

      t.timestamps
    end
    add_index :workday_manual_entries, [:staff_id, :year_month], unique: true
  end
end
